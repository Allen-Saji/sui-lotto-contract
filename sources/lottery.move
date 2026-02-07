module sui_lotto::lottery {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::event;
    use sui::random::{Self, Random, RandomGenerator};
    use sui::clock::Clock;

    // === Errors ===
    const ELotteryNotActive: u64 = 0;
    const EDeadlineNotReached: u64 = 1;
    const EInvalidTicketPrice: u64 = 2;
    const ENotEnoughParticipants: u64 = 3;
    const ELotteryAlreadyCompleted: u64 = 4;
    const ERefundNotAvailable: u64 = 5;
    const ENotAParticipant: u64 = 6;
    const EDeadlinePassed: u64 = 7;
    const EInvalidDeadline: u64 = 8;

    // === Constants ===
    const STATUS_ACTIVE: u8 = 0;
    const STATUS_COMPLETED: u8 = 1;
    const ADMIN_FEE_BPS: u16 = 200;
    const BPS_DENOMINATOR: u64 = 10000;
    const MIN_PARTICIPANTS: u64 = 2;

    const THRESHOLD_2_WINNERS: u64 = 6;
    const THRESHOLD_3_WINNERS: u64 = 10;
    const THRESHOLD_5_WINNERS: u64 = 100;

    // === Structs ===
    public struct AdminCap has key, store {
        id: UID,
    }

    public struct Lottery has key {
        id: UID,
        ticket_price: u64,
        balance: Balance<SUI>,
        participants: vector<address>,
        deadline: u64,
        status: u8,
        winners: vector<address>,
        admin_fee_bps: u16,
    }

    // === Events ===
    public struct LotteryCreatedEvent has copy, drop {
        lottery_id: ID,
        ticket_price: u64,
        deadline: u64,
    }

    public struct TicketPurchasedEvent has copy, drop {
        lottery_id: ID,
        buyer: address,
        tickets_bought: u64,
        total_pool: u64,
    }

    public struct WinnersSelectedEvent has copy, drop {
        lottery_id: ID,
        winners: vector<address>,
        prize_per_winner: u64,
        total_prize: u64,
        admin_fee: u64,
    }

    public struct RefundClaimedEvent has copy, drop {
        lottery_id: ID,
        claimant: address,
        amount: u64,
    }

    // === Init ===
    fun init(ctx: &mut TxContext) {
        transfer::transfer(
            AdminCap { id: object::new(ctx) },
            ctx.sender()
        );
    }

    // === Admin Functions ===
    /// Create a new lottery round
    /// - ticket_price: Price per ticket in MIST
    /// - deadline: Unix timestamp in milliseconds when lottery ends
    public fun create_lottery(
        _cap: &AdminCap,
        ticket_price: u64,
        deadline: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate deadline is in the future
        assert!(deadline > clock.timestamp_ms(), EInvalidDeadline);
        // Validate ticket price is non-zero
        assert!(ticket_price > 0, EInvalidTicketPrice);

        let lottery = Lottery {
            id: object::new(ctx),
            ticket_price,
            balance: balance::zero(),
            participants: vector::empty(),
            deadline,
            status: STATUS_ACTIVE,
            winners: vector::empty(),
            admin_fee_bps: ADMIN_FEE_BPS,
        };

        event::emit(LotteryCreatedEvent {
            lottery_id: object::id(&lottery),
            ticket_price,
            deadline,
        });

        transfer::share_object(lottery);
    }

    /// Draw winners and distribute funds
    /// Winner count: 1 (2-5 players), 2 (6-9), 3 (10-99), 5 (100+)
    /// Uses Sui's native randomness - MUST be entry to prevent composition attacks
    entry fun draw_winner(
        lottery: &mut Lottery,
        _cap: &AdminCap,
        r: &Random,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate lottery state
        assert!(lottery.status == STATUS_ACTIVE, ELotteryAlreadyCompleted);
        assert!(clock.timestamp_ms() >= lottery.deadline, EDeadlineNotReached);
        let total_tickets = vector::length(&lottery.participants);
        assert!(total_tickets >= MIN_PARTICIPANTS, ENotEnoughParticipants);

        // Determine number of winners based on participant count
        let num_winners = get_winner_count(total_tickets);

        // Generate random winners
        let mut generator = random::new_generator(r, ctx);
        let winners = select_winners(&mut generator, &lottery.participants, num_winners);

        // Calculate prize distribution
        let total_pool = balance::value(&lottery.balance);
        let admin_fee = (total_pool * (lottery.admin_fee_bps as u64)) / BPS_DENOMINATOR;
        let total_prize = total_pool - admin_fee;
        let prize_per_winner = total_prize / (num_winners as u64);

        // Handle remainder (dust) - add to first winner's prize
        let remainder = total_prize - (prize_per_winner * (num_winners as u64));

        // Transfer prizes to winners
        let mut i = 0;
        while (i < num_winners) {
            let winner = *vector::borrow(&winners, (i as u64));
            let prize_amount = if (i == 0) {
                prize_per_winner + remainder // First winner gets the dust
            } else {
                prize_per_winner
            };
            let prize = coin::take(&mut lottery.balance, prize_amount, ctx);
            transfer::public_transfer(prize, winner);
            i = i + 1;
        };

        // Transfer admin fee to caller (admin)
        if (admin_fee > 0) {
            let fee = coin::take(&mut lottery.balance, admin_fee, ctx);
            transfer::public_transfer(fee, ctx.sender());
        };

        // Update lottery state
        lottery.status = STATUS_COMPLETED;
        lottery.winners = winners;

        event::emit(WinnersSelectedEvent {
            lottery_id: object::id(lottery),
            winners: lottery.winners,
            prize_per_winner,
            total_prize,
            admin_fee,
        });
    }

    // === Internal Functions ===
    /// Determine number of winners based on participant count
    fun get_winner_count(participant_count: u64): u8 {
        if (participant_count >= THRESHOLD_5_WINNERS) {
            5
        } else if (participant_count >= THRESHOLD_3_WINNERS) {
            3
        } else if (participant_count >= THRESHOLD_2_WINNERS) {
            2
        } else {
            1
        }
    }

    /// Select random winners from participants
    /// Same address CAN win multiple times if they hold multiple tickets
    fun select_winners(
        generator: &mut RandomGenerator,
        participants: &vector<address>,
        num_winners: u8
    ): vector<address> {
        let mut winners = vector::empty<address>();
        let total = vector::length(participants);

        // Create a mutable copy of indices to pick from
        let mut available_indices = vector::empty<u64>();
        let mut i = 0;
        while (i < total) {
            vector::push_back(&mut available_indices, i);
            i = i + 1;
        };

        // Pick winners without replacement (same ticket can't win twice)
        let mut picked = 0u8;
        while (picked < num_winners && vector::length(&available_indices) > 0) {
            let remaining = vector::length(&available_indices);
            let rand_idx = random::generate_u64_in_range(generator, 0, remaining - 1);
            let winner_idx = vector::remove(&mut available_indices, rand_idx);
            let winner = *vector::borrow(participants, winner_idx);
            vector::push_back(&mut winners, winner);
            picked = picked + 1;
        };

        winners
    }

    // === Player Functions ===
    /// Purchase ticket(s) with exact SUI payment
    /// Each ticket_price worth of SUI = 1 ticket
    public fun buy_ticket(
        lottery: &mut Lottery,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate lottery is active and deadline not passed
        assert!(lottery.status == STATUS_ACTIVE, ELotteryNotActive);
        assert!(clock.timestamp_ms() < lottery.deadline, EDeadlinePassed);

        let payment_value = coin::value(&payment);
        assert!(payment_value >= lottery.ticket_price, EInvalidTicketPrice);
        assert!(payment_value % lottery.ticket_price == 0, EInvalidTicketPrice);

        let tickets_bought = payment_value / lottery.ticket_price;
        let buyer = ctx.sender();

        // Add buyer address for each ticket purchased
        let mut i = 0;
        while (i < tickets_bought) {
            vector::push_back(&mut lottery.participants, buyer);
            i = i + 1;
        };

        // Add payment to prize pool
        coin::put(&mut lottery.balance, payment);

        event::emit(TicketPurchasedEvent {
            lottery_id: object::id(lottery),
            buyer,
            tickets_bought,
            total_pool: balance::value(&lottery.balance),
        });
    }

    /// Claim refund if lottery deadline passed with < 2 participants
    #[allow(lint(self_transfer))]
    public fun claim_refund(
        lottery: &mut Lottery,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate refund conditions
        assert!(lottery.status == STATUS_ACTIVE, ELotteryAlreadyCompleted);
        assert!(clock.timestamp_ms() >= lottery.deadline, ERefundNotAvailable);
        assert!(vector::length(&lottery.participants) < MIN_PARTICIPANTS, ERefundNotAvailable);

        let claimant = ctx.sender();

        // Count tickets owned by claimant and remove them
        let mut refund_tickets = 0u64;
        let mut i = 0;
        while (i < vector::length(&lottery.participants)) {
            if (*vector::borrow(&lottery.participants, i) == claimant) {
                vector::remove(&mut lottery.participants, i);
                refund_tickets = refund_tickets + 1;
                // Don't increment i since we removed an element
            } else {
                i = i + 1;
            };
        };

        assert!(refund_tickets > 0, ENotAParticipant);

        // Calculate and transfer refund
        let refund_amount = refund_tickets * lottery.ticket_price;
        let refund = coin::take(&mut lottery.balance, refund_amount, ctx);
        transfer::public_transfer(refund, claimant);

        event::emit(RefundClaimedEvent {
            lottery_id: object::id(lottery),
            claimant,
            amount: refund_amount,
        });
    }

    // === View Functions ===
    public fun get_pool_size(lottery: &Lottery): u64 {
        balance::value(&lottery.balance)
    }

    public fun get_participant_count(lottery: &Lottery): u64 {
        vector::length(&lottery.participants)
    }

    public fun get_deadline(lottery: &Lottery): u64 {
        lottery.deadline
    }

    public fun is_active(lottery: &Lottery, clock: &Clock): bool {
        lottery.status == STATUS_ACTIVE && clock.timestamp_ms() < lottery.deadline
    }

    public fun get_ticket_price(lottery: &Lottery): u64 {
        lottery.ticket_price
    }

    public fun get_winners(lottery: &Lottery): vector<address> {
        lottery.winners
    }

    public fun get_expected_winner_count(participant_count: u64): u8 {
        get_winner_count(participant_count)
    }

    public fun get_status(lottery: &Lottery): u8 {
        lottery.status
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
