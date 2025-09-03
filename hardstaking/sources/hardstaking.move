module hardstaking::staking {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::table::{Self, Table};

    // Import your custom token type
    use niranjan_token::niranjan_token::NIRANJAN_TOKEN;


    // Error codes
    const EInvalidStakingPeriod: u64 = 1;
    const EStakingNotMatured: u64 = 2;
    const EInsufficientRewards: u64 = 3;
    const EStakeNotFound: u64 = 4;
    const EInvalidAmount: u64 = 6;

    // Constants
    const MIN_STAKE_AMOUNT: u64 = 1_000_000_000; // 1 token min (adjust decimals as needed)
    const SECONDS_IN_DAY: u64 = 86400;

    // Supported staking periods
    const PERIOD_30_DAYS: u64 = 30;
    const PERIOD_90_DAYS: u64 = 90;
    const PERIOD_180_DAYS: u64 = 180;
    const PERIOD_365_DAYS: u64 = 365;

    // APY (basis points, 100 = 1%)
    const APY_30_DAYS: u64 = 500;   // 5%
    const APY_90_DAYS: u64 = 1000;  // 10%
    const APY_180_DAYS: u64 = 1500; // 15%
    const APY_365_DAYS: u64 = 2000; // 20%

    // Pool object
    public struct StakingPool has key {
        id: UID,
        admin: address,
        total_staked: u64,
        total_rewards_distributed: u64,
        reward_pool: Balance<NIRANJAN_TOKEN>,
        stakes: Table<address, vector<Stake>>,
        next_stake_id: u64,
    }

    // Individual stake details
    public struct Stake has store, copy, drop {
        id: u64,
        amount: u64,
        start_time: u64,
        end_time: u64,
        apy: u64,
        claimed: bool,
    }

    public struct AdminCap has key { id: UID }

    // Events
    public struct StakeCreated has copy, drop {
        staker: address,
        stake_id: u64,
        amount: u64,
        start_time: u64,
        end_time: u64,
        apy: u64,
    }
    public struct StakeClaimed has copy, drop {
        staker: address,
        stake_id: u64,
        principal: u64,
        reward: u64,
        total_claimed: u64,
    }
    public struct RewardsAdded has copy, drop {
        amount: u64,
        new_total: u64,
    }

    // Init
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        let pool = StakingPool {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            total_staked: 0,
            total_rewards_distributed: 0,
            reward_pool: balance::zero<NIRANJAN_TOKEN>(),
            stakes: table::new<address, vector<Stake>>(ctx),
            next_stake_id: 1,
        };
        transfer::share_object(pool);
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    // Stake
    public fun stake(
        pool: &mut StakingPool,
        stake_coin: Coin<NIRANJAN_TOKEN>,
        period_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&stake_coin);
        assert!(amount >= MIN_STAKE_AMOUNT, EInvalidAmount);

        let apy = get_apy_for_period(period_days);
        assert!(apy > 0, EInvalidStakingPeriod);

        let staker = tx_context::sender(ctx);
        let start_time = clock::timestamp_ms(clock);
        let end_time = start_time + (period_days * SECONDS_IN_DAY * 1000);

        let stake = Stake { id: pool.next_stake_id, amount, start_time, end_time, apy, claimed: false };

        if (!table::contains(&pool.stakes, staker)) {
            table::add(&mut pool.stakes, staker, vector::empty<Stake>());
        };
        let user_stakes = table::borrow_mut(&mut pool.stakes, staker);
        vector::push_back(user_stakes, stake);

        pool.total_staked = pool.total_staked + amount;
        pool.next_stake_id = pool.next_stake_id + 1;

        let stake_balance = coin::into_balance(stake_coin);
        balance::join(&mut pool.reward_pool, stake_balance);

        event::emit(StakeCreated { staker, stake_id: stake.id, amount, start_time, end_time, apy });
    }

    // Claim
    public fun claim_stake(
        pool: &mut StakingPool,
        stake_id: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let staker = tx_context::sender(ctx);
        assert!(table::contains(&pool.stakes, staker), EStakeNotFound);

        let user_stakes = table::borrow_mut(&mut pool.stakes, staker);
        let (stake_index, stake) = find_stake_by_id(user_stakes, stake_id);

        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= stake.end_time, EStakingNotMatured);
        assert!(!stake.claimed, EStakeNotFound);

        let reward = calculate_reward(stake.amount, stake.apy, (stake.end_time - stake.start_time) / 1000);
        let total_payout = stake.amount + reward;
        assert!(balance::value(&pool.reward_pool) >= total_payout, EInsufficientRewards);

        let stake_mut = vector::borrow_mut(user_stakes, stake_index);
        stake_mut.claimed = true;

        pool.total_rewards_distributed = pool.total_rewards_distributed + reward;

        let payout_balance = balance::split(&mut pool.reward_pool, total_payout);
        let payout_coin = coin::from_balance(payout_balance, ctx);
        transfer::public_transfer(payout_coin, staker);

        event::emit(StakeClaimed { staker, stake_id, principal: stake.amount, reward, total_claimed: total_payout });
    }

    // Admin add rewards
    public fun add_rewards(
        _: &AdminCap,
        pool: &mut StakingPool,
        reward_coin: Coin<NIRANJAN_TOKEN>,
        _ctx: &mut TxContext
    ) {
        let amount = coin::value(&reward_coin);
        let reward_balance = coin::into_balance(reward_coin);
        balance::join(&mut pool.reward_pool, reward_balance);

        let new_total = balance::value(&pool.reward_pool);
        event::emit(RewardsAdded { amount, new_total });
    }

    // View functions
    public fun get_user_stakes(pool: &StakingPool, user: address): vector<Stake> {
        if (table::contains(&pool.stakes, user)) {
            *table::borrow(&pool.stakes, user)
        } else {
            vector::empty<Stake>()
        }
    }

    public fun get_pool_stats(pool: &StakingPool): (u64, u64, u64, u64) {
        (pool.total_staked, pool.total_rewards_distributed, balance::value(&pool.reward_pool), pool.next_stake_id - 1)
    }

    public fun calculate_potential_reward(amount: u64, period_days: u64): u64 {
        let apy = get_apy_for_period(period_days);
        calculate_reward(amount, apy, period_days * SECONDS_IN_DAY)
    }

    // Helpers
    fun get_apy_for_period(period_days: u64): u64 {
        if (period_days == PERIOD_30_DAYS) { APY_30_DAYS }
        else if (period_days == PERIOD_90_DAYS) { APY_90_DAYS }
        else if (period_days == PERIOD_180_DAYS) { APY_180_DAYS }
        else if (period_days == PERIOD_365_DAYS) { APY_365_DAYS }
        else { 0 }
    }

    fun calculate_reward(amount: u64, apy_bp: u64, duration_seconds: u64): u64 {
        let annual_seconds = 365 * SECONDS_IN_DAY;
        (amount * apy_bp * duration_seconds) / (10000 * annual_seconds)
    }

    fun find_stake_by_id(stakes: &vector<Stake>, stake_id: u64): (u64, Stake) {
        let mut i = 0;
        let len = vector::length(stakes);

        while (i < len) {
            let stake = *vector::borrow(stakes, i);
            if (stake.id == stake_id && !stake.claimed) {
                return (i, stake)
            };
            i = i + 1;
        };
        
        abort EStakeNotFound
    }

    // Testing helpers
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun get_reward_pool_balance(pool: &StakingPool): u64 {
        balance::value(&pool.reward_pool)
    }

    public fun get_stake_amount(stake: &Stake): u64 {
        stake.amount
    }

    public fun get_stake_id(stake: &Stake): u64 {
        stake.id
    }
        // Unstake = claim back principal + rewards
    public fun unstake(
        pool: &mut StakingPool,
        stake_id: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<NIRANJAN_TOKEN> {
        let staker = tx_context::sender(ctx);
        assert!(table::contains(&pool.stakes, staker), EStakeNotFound);

        let user_stakes = table::borrow_mut(&mut pool.stakes, staker);
        let (stake_index, stake) = find_stake_by_id(user_stakes, stake_id);

        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= stake.end_time, EStakingNotMatured);
        assert!(!stake.claimed, EStakeNotFound);

        // calculate rewards
        let reward = calculate_reward(
            stake.amount,
            stake.apy,
            (stake.end_time - stake.start_time) / 1000
        );
        let total_payout = stake.amount + reward;
        assert!(balance::value(&pool.reward_pool) >= total_payout, EInsufficientRewards);

        // mark as claimed
        let stake_mut = vector::borrow_mut(user_stakes, stake_index);
        stake_mut.claimed = true;

        pool.total_rewards_distributed = pool.total_rewards_distributed + reward;

        // payout
        let payout_balance = balance::split(&mut pool.reward_pool, total_payout);
        let payout_coin = coin::from_balance(payout_balance, ctx);

        event::emit(StakeClaimed {
            staker,
            stake_id,
            principal: stake.amount,
            reward,
            total_claimed: total_payout
        });

        payout_coin
    }

}
