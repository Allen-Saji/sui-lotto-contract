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

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
