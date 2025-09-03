#[test_only]
module hardstaking::hardstaking_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Coin, TreasuryCap, value};
    use sui::clock::Clock;
    use niranjan_token::niranjan_token::{NIRANJAN_TOKEN};
    use niranjan_token::niranjan_token as token;
    use hardstaking::staking::{Self, StakingPool, AdminCap, Stake};

    const ADMIN: address = @0xABCD;
    const USER1: address = @0xBEEF;
    const ONE: u64 = 1_000_000_000;

    #[test]
    fun test_initialize_pool() {
    let mut scenario = test_scenario::begin(ADMIN);

    // TX 1: init
    {
        let ctx = test_scenario::ctx(&mut scenario);
        staking::init_for_testing(ctx);
    }; // <-- semicolon after closing block
    test_scenario::next_tx(&mut scenario, ADMIN);

    assert!(test_scenario::has_most_recent_shared<StakingPool>(), 0);
    assert!(test_scenario::has_most_recent_for_address<AdminCap>(ADMIN), 0);

    test_scenario::end(scenario);
}
#[test]
fun test_stake_and_unstake() {
    let mut scenario = test_scenario::begin(ADMIN);

    // TX1: init
    {
        let ctx = test_scenario::ctx(&mut scenario);
        staking::init_for_testing(ctx);
    };
    test_scenario::next_tx(&mut scenario, ADMIN);

    // TX2: mint
    {
        let mut cap = test_scenario::take_from_address<TreasuryCap<NIRANJAN_TOKEN>>(&mut scenario, ADMIN);
        let ctx = test_scenario::ctx(&mut scenario);
        token::mint(&mut cap, ONE, USER1, ctx);

        // Return cap so it isn't lost
        test_scenario::return_to_address(ADMIN, cap);
    };
    test_scenario::next_tx(&mut scenario, ADMIN);

    // TX3: stake
    {
        let coin = test_scenario::take_from_address<Coin<NIRANJAN_TOKEN>>(&mut scenario, USER1);
        let mut pool = test_scenario::take_shared<StakingPool>(&mut scenario);
        let clock = test_scenario::take_shared<Clock>(&mut scenario);
        let ctx = test_scenario::ctx(&mut scenario);

        staking::stake(&mut pool, coin, 30, &clock, ctx);

        // Return pool and clock to avoid "unused without drop"
        test_scenario::return_to_address(ADMIN, pool);
        test_scenario::return_to_address(ADMIN, clock);
    };
    test_scenario::next_tx(&mut scenario, USER1);

    test_scenario::end(scenario);
}
}