#[test_only]
module sui_lotto::lottery_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::random::{Self, Random};
    use sui_lotto::lottery::{Self, Lottery, AdminCap};

    // Test addresses
    const ADMIN: address = @0xAD;
    const PLAYER1: address = @0x1;
    const PLAYER2: address = @0x2;
    const PLAYER3: address = @0x3;
    const PLAYER4: address = @0x4;
    const PLAYER5: address = @0x5;
    const PLAYER6: address = @0x6;

    // Test constants
    const TICKET_PRICE: u64 = 1_000_000_000; // 1 SUI
    const ONE_HOUR_MS: u64 = 3_600_000;

    // === Helper Functions ===
    fun setup_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(ts::ctx(scenario))
    }

    fun setup_random_state(scenario: &mut Scenario) {
        ts::next_tx(scenario, @0x0);
        {
            random::create_for_testing(ts::ctx(scenario));
        };
        ts::next_tx(scenario, ADMIN);
    }

    fun mint_sui(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
    }

    fun buy_ticket_for(scenario: &mut Scenario, player: address, clock: &Clock, num_tickets: u64) {
        ts::next_tx(scenario, player);
        {
            let mut lottery = ts::take_shared<Lottery>(scenario);
            let payment = mint_sui(TICKET_PRICE * num_tickets, scenario);
            lottery::buy_ticket(&mut lottery, payment, clock, ts::ctx(scenario));
            ts::return_shared(lottery);
        };
    }

    // === Init Tests ===
    #[test]
    fun test_init_creates_admin_cap() {
        let mut scenario = ts::begin(ADMIN);
        {
            lottery::init_for_testing(ts::ctx(&mut scenario));
        };
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
        };
        ts::end(scenario);
    }

    // === Create Lottery Tests ===
    #[test]
    fun test_create_lottery() {
        let mut scenario = ts::begin(ADMIN);
        let clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let lottery = ts::take_shared<Lottery>(&scenario);
            assert!(lottery::get_ticket_price(&lottery) == TICKET_PRICE, 0);
            assert!(lottery::get_pool_size(&lottery) == 0, 1);
            assert!(lottery::get_participant_count(&lottery) == 0, 2);
            assert!(lottery::is_active(&lottery, &clock), 3);
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::EInvalidDeadline)]
    fun test_create_lottery_invalid_deadline() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);
        clock::set_for_testing(&mut clock, 1000);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            lottery::create_lottery(&cap, TICKET_PRICE, 500, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::EInvalidTicketPrice)]
    fun test_create_lottery_zero_price() {
        let mut scenario = ts::begin(ADMIN);
        let clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, 0, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // === Buy Ticket Tests ===
    #[test]
    fun test_buy_single_ticket() {
        let mut scenario = ts::begin(ADMIN);
        let clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let payment = mint_sui(TICKET_PRICE, &mut scenario);
            lottery::buy_ticket(&mut lottery, payment, &clock, ts::ctx(&mut scenario));
            assert!(lottery::get_pool_size(&lottery) == TICKET_PRICE, 0);
            assert!(lottery::get_participant_count(&lottery) == 1, 1);
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_buy_multiple_tickets() {
        let mut scenario = ts::begin(ADMIN);
        let clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let payment = mint_sui(TICKET_PRICE * 3, &mut scenario);
            lottery::buy_ticket(&mut lottery, payment, &clock, ts::ctx(&mut scenario));
            assert!(lottery::get_pool_size(&lottery) == TICKET_PRICE * 3, 0);
            assert!(lottery::get_participant_count(&lottery) == 3, 1);
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::EInvalidTicketPrice)]
    fun test_buy_ticket_insufficient_payment() {
        let mut scenario = ts::begin(ADMIN);
        let clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let payment = mint_sui(TICKET_PRICE - 1, &mut scenario);
            lottery::buy_ticket(&mut lottery, payment, &clock, ts::ctx(&mut scenario));
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::EDeadlinePassed)]
    fun test_buy_ticket_after_deadline() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let payment = mint_sui(TICKET_PRICE, &mut scenario);
            lottery::buy_ticket(&mut lottery, payment, &clock, ts::ctx(&mut scenario));
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // === Winner Count Tests ===
    #[test]
    fun test_winner_count_thresholds() {
        // 2-5 players = 1 winner
        assert!(lottery::get_expected_winner_count(2) == 1, 0);
        assert!(lottery::get_expected_winner_count(5) == 1, 1);

        // 6-9 players = 2 winners
        assert!(lottery::get_expected_winner_count(6) == 2, 2);
        assert!(lottery::get_expected_winner_count(9) == 2, 3);

        // 10-99 players = 3 winners
        assert!(lottery::get_expected_winner_count(10) == 3, 4);
        assert!(lottery::get_expected_winner_count(99) == 3, 5);

        // 100+ players = 5 winners
        assert!(lottery::get_expected_winner_count(100) == 5, 6);
        assert!(lottery::get_expected_winner_count(1000) == 5, 7);
    }

    // === Draw Winner Tests ===
    #[test]
    fun test_draw_winner_2_players_1_winner() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);
        setup_random_state(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        // 2 players buy tickets
        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER2, &clock, 1);

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let random = ts::take_shared<Random>(&scenario);

            lottery::draw_winner(&mut lottery, &cap, &random, &clock, ts::ctx(&mut scenario));

            assert!(lottery::get_status(&lottery) == 1, 0);
            let winners = lottery::get_winners(&lottery);
            assert!(vector::length(&winners) == 1, 1);

            ts::return_shared(lottery);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(random);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_draw_winner_6_players_2_winners() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);
        setup_random_state(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        // 6 players buy tickets
        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER2, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER3, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER4, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER5, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER6, &clock, 1);

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let random = ts::take_shared<Random>(&scenario);

            lottery::draw_winner(&mut lottery, &cap, &random, &clock, ts::ctx(&mut scenario));

            assert!(lottery::get_status(&lottery) == 1, 0);
            let winners = lottery::get_winners(&lottery);
            assert!(vector::length(&winners) == 2, 1);

            ts::return_shared(lottery);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(random);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_draw_winner_10_players_3_winners() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);
        setup_random_state(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        // Player1 buys 10 tickets (simulates 10 participants)
        buy_ticket_for(&mut scenario, PLAYER1, &clock, 10);

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let random = ts::take_shared<Random>(&scenario);

            lottery::draw_winner(&mut lottery, &cap, &random, &clock, ts::ctx(&mut scenario));

            assert!(lottery::get_status(&lottery) == 1, 0);
            let winners = lottery::get_winners(&lottery);
            assert!(vector::length(&winners) == 3, 1);

            ts::return_shared(lottery);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(random);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::EDeadlineNotReached)]
    fun test_draw_before_deadline() {
        let mut scenario = ts::begin(ADMIN);
        let clock = setup_clock(&mut scenario);
        setup_random_state(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER2, &clock, 1);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let random = ts::take_shared<Random>(&scenario);

            lottery::draw_winner(&mut lottery, &cap, &random, &clock, ts::ctx(&mut scenario));

            ts::return_shared(lottery);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(random);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::ENotEnoughParticipants)]
    fun test_draw_not_enough_participants() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);
        setup_random_state(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let random = ts::take_shared<Random>(&scenario);

            lottery::draw_winner(&mut lottery, &cap, &random, &clock, ts::ctx(&mut scenario));

            ts::return_shared(lottery);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(random);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::ELotteryAlreadyCompleted)]
    fun test_draw_twice() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);
        setup_random_state(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);
        buy_ticket_for(&mut scenario, PLAYER2, &clock, 1);

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        // First draw
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let random = ts::take_shared<Random>(&scenario);
            lottery::draw_winner(&mut lottery, &cap, &random, &clock, ts::ctx(&mut scenario));
            ts::return_shared(lottery);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(random);
        };

        // Second draw - should fail
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let random = ts::take_shared<Random>(&scenario);
            lottery::draw_winner(&mut lottery, &cap, &random, &clock, ts::ctx(&mut scenario));
            ts::return_shared(lottery);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(random);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // === Refund Tests ===
    #[test]
    fun test_claim_refund_single_participant() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            lottery::claim_refund(&mut lottery, &clock, ts::ctx(&mut scenario));
            assert!(lottery::get_pool_size(&lottery) == 0, 0);
            assert!(lottery::get_participant_count(&lottery) == 0, 1);
            ts::return_shared(lottery);
        };

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&coin) == TICKET_PRICE, 0);
            ts::return_to_sender(&scenario, coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::ERefundNotAvailable)]
    fun test_refund_not_available_before_deadline() {
        let mut scenario = ts::begin(ADMIN);
        let clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            lottery::claim_refund(&mut lottery, &clock, ts::ctx(&mut scenario));
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = lottery::ENotAParticipant)]
    fun test_refund_not_participant() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        buy_ticket_for(&mut scenario, PLAYER1, &clock, 1);

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, PLAYER2);
        {
            let mut lottery = ts::take_shared<Lottery>(&scenario);
            lottery::claim_refund(&mut lottery, &clock, ts::ctx(&mut scenario));
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // === View Function Tests ===
    #[test]
    fun test_is_active() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = setup_clock(&mut scenario);

        lottery::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, ADMIN);

        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let deadline = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
            lottery::create_lottery(&cap, TICKET_PRICE, deadline, &clock, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, cap);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let lottery = ts::take_shared<Lottery>(&scenario);
            assert!(lottery::is_active(&lottery, &clock), 0);
            ts::return_shared(lottery);
        };

        clock::set_for_testing(&mut clock, ONE_HOUR_MS + 1);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let lottery = ts::take_shared<Lottery>(&scenario);
            assert!(!lottery::is_active(&lottery, &clock), 0);
            ts::return_shared(lottery);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
