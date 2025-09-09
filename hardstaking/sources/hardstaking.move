module hardstaking::staking {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::table::{Self, Table};
    use niranjan_token::niranjan_token::NIRANJAN_TOKEN;


    //  Errors 
    const EInvalidStakingPeriod: u64 = 1;
    const EStakingNotMatured: u64 = 2;
    const EInsufficientRewards: u64 = 3;
    const EStakeNotFound: u64 = 4;
    const EInvalidAmount: u64 = 6;
    const ENotOwner: u64 = 100;
    const ENotAdmin: u64 = 101;
    const EAdminExists: u64 = 102;
    const EAdminNotFound: u64 = 103;
    const EMaxAdminsReached: u64 = 104;


    // Constants 
    const MIN_STAKE_AMOUNT: u64 = 1_000_000_000; // 1 token min (in smallest unit)
    const SECONDS_IN_DAY: u64 = 86400;
    const PERIOD_30_DAYS: u64 = 30;
    const PERIOD_90_DAYS: u64 = 90;
    const PERIOD_180_DAYS: u64 = 180;
    const PERIOD_365_DAYS: u64 = 365;
    const APY_30_DAYS: u64 = 500;   // 5% APY, represented in basis points
    const APY_90_DAYS: u64 = 1000;  // 10% APY
    const APY_180_DAYS: u64 = 1500; // 15% APY
    const APY_365_DAYS: u64 = 2000; // 20% APY


   
    public struct StakingPool has key {
        id: UID,                               
        owner: address,                         
        total_staked: u64,                   
        total_rewards_distributed: u64,      
        staked_tokens: Balance<NIRANJAN_TOKEN>,
        reward_pool: Balance<NIRANJAN_TOKEN>,    
        stakes: Table<address, vector<Stake>>,    
        next_stake_id: u64,                       
        admins: Table<address, bool>,              
        admin_count: u64,                          
        paused: bool,                              
    }


    // Individual stake details struct
    public struct Stake has store, copy, drop {
        id: u64,           
        amount: u64,       
        start_time: u64,   
        end_time: u64,     
        apy: u64,          
        claimed: bool,     
    }


    // Capability struct to manage admin privileges 
    public struct AdminCap has key { id: UID }


    // Event emitted when a new stake is created
    public struct StakeCreated has copy, drop {
        staker: address,
        stake_id: u64,
        amount: u64,
        start_time: u64,
        end_time: u64,
        apy: u64,
    }


    // Event emitted upon successful stake claim
    public struct StakeClaimed has copy, drop {
        staker: address,
        stake_id: u64,
        principal: u64,
        reward: u64,
        total_claimed: u64,
    }


    // Event emitted when new rewards are added to the pool
    public struct RewardsAdded has copy, drop {
        amount: u64,
        new_total: u64,
    }


    // Event emitted when a new admin is added to pool
    public struct AdminAdded has copy, drop {
        owner: address,
        new_admin: address,
        total_admins: u64,
    }


    // Event emitted when an admin is removed
    public struct AdminRemoved has copy, drop {
        owner: address,
        admin: address,
        total_admins: u64,
    }


    // Event emitted when the pool is paused by admin
    public struct PoolPaused has copy, drop { admin: address }
    // Event emitted when the pool is unpaused by admin
    public struct PoolUnpaused has copy, drop { admin: address }


    // Initialize staking pool; sets the caller as owner and admin
    fun init(ctx: &mut TxContext) {
        let owner_addr = tx_context::sender(ctx);
        let admin_cap = AdminCap { id: object::new(ctx) };
        let pool = StakingPool {
            id: object::new(ctx),
            owner: owner_addr,
            total_staked: 0,
            total_rewards_distributed: 0,
            staked_tokens: balance::zero<NIRANJAN_TOKEN>(),
            reward_pool: balance::zero<NIRANJAN_TOKEN>(),
            stakes: table::new<address, vector<Stake>>(ctx),
            next_stake_id: 1,
            admins: table::new<address, bool>(ctx),
            admin_count: 0,
            paused: false,
        };
        transfer::share_object(pool);
        transfer::transfer(admin_cap, owner_addr);
    }


    // Add a new admin by owner only; prevents duplicates and limits max admins
    public fun add_admin(pool: &mut StakingPool, new_admin: address, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == pool.owner, ENotOwner);
        assert!(pool.admin_count < 2, EMaxAdminsReached);
        if (table::contains(&pool.admins, new_admin)) { abort EAdminExists };
        table::add(&mut pool.admins, new_admin, true);
        pool.admin_count = pool.admin_count + 1;
        event::emit(AdminAdded { owner: pool.owner, new_admin, total_admins: pool.admin_count });
    }


    // Remove an admin by owner only; ensures admin exists before removal
    public fun remove_admin(pool: &mut StakingPool, admin_addr: address, ctx: &TxContext) {
        assert!(tx_context::sender(ctx) == pool.owner, ENotOwner);
        if (!table::contains(&pool.admins, admin_addr)) { abort EAdminNotFound };
        table::remove(&mut pool.admins, admin_addr);
        if (pool.admin_count > 0) { pool.admin_count = pool.admin_count - 1 };
        event::emit(AdminRemoved { owner: pool.owner, admin: admin_addr, total_admins: pool.admin_count });
    }


    // Check if address is registered as an admin
    fun is_admin(pool: &StakingPool, addr: address): bool {
        if (table::contains(&pool.admins, addr)) {
            *table::borrow(&pool.admins, addr)
        } else {
            false
        }
    }


    // Assert sender is either pool owner or an admin; abort if neither
    fun assert_admin_or_owner(pool: &StakingPool, sender: address) {
        if (!(sender == pool.owner || is_admin(pool, sender))) {
            abort ENotAdmin
        }
    }


    // Admin function to pause staking and claiming actions in the pool
    public fun pause(pool: &mut StakingPool, ctx: &TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(is_admin(pool, sender), ENotAdmin);
        pool.paused = true;
        event::emit(PoolPaused { admin: sender });
    }


    // Admin function to unpause the pool and resume staking/claiming
    public fun unpause(pool: &mut StakingPool, ctx: &TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(is_admin(pool, sender), ENotAdmin);
        pool.paused = false;
        event::emit(PoolUnpaused { admin: sender });
    }


    // User stakes tokens for a chosen period. Pool must be active (not paused)
    public fun stake(
        pool: &mut StakingPool,
        stake_coin: Coin<NIRANJAN_TOKEN>,
        period_days: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!pool.paused, ENotAdmin);
        let amount = coin::value(&stake_coin);
        assert!(amount >= MIN_STAKE_AMOUNT, EInvalidAmount);

        // Get APY for requested staking period; must be valid
        let apy = get_apy_for_period(period_days);
        assert!(apy > 0, EInvalidStakingPeriod);

        // Get the staker address and current timestamp
        let staker = tx_context::sender(ctx);
        let start_time = clock::timestamp_ms(clock);
        let end_time = start_time + (period_days * SECONDS_IN_DAY * 1000);

        // Create new stake record with unique ID
        let stake = Stake {
            id: pool.next_stake_id,
            amount,
            start_time,
            end_time,
            apy,
            claimed: false,
        };

        // If user has no stakes yet, add an empty vector to pool
        if (!table::contains(&pool.stakes, staker)) {
            table::add(&mut pool.stakes, staker, vector::empty<Stake>());
        };
        let user_stakes = table::borrow_mut(&mut pool.stakes, staker);
        vector::push_back(user_stakes, stake);

        // Update pool totals and increment stake ID counter
        pool.total_staked = pool.total_staked + amount;
        pool.next_stake_id = pool.next_stake_id + 1;

        // Convert stake coin into pool's staked_tokens balance
        let stake_balance = coin::into_balance(stake_coin);
        balance::join(&mut pool.staked_tokens, stake_balance);

        // Emit event indicating successful stake creation
        event::emit(StakeCreated {
            staker,
            stake_id: stake.id,
            amount,
            start_time,
            end_time,
            apy
        });
    }


    // Claim staked tokens and rewards after maturity; fails if early or already claimed
    public fun claim_stake(
        pool: &mut StakingPool,
        stake_id: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<NIRANJAN_TOKEN> {
        let staker = tx_context::sender(ctx);
        assert!(table::contains(&pool.stakes, staker), EStakeNotFound);

        // Locate the stake by ID
        let user_stakes = table::borrow_mut(&mut pool.stakes, staker);
        let (stake_index, stake) = find_stake_by_id(user_stakes, stake_id);

        // Ensure that staking period has ended
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= stake.end_time, EStakingNotMatured);
        assert!(!stake.claimed, EStakeNotFound);

        // Calculate staking reward based on amount, APY and duration
        let reward = calculate_reward(stake.amount, stake.apy, (stake.end_time - stake.start_time) / 1000);

        // Verify availability of funds for reward and principal payout
        assert!(balance::value(&pool.reward_pool) >= reward, EInsufficientRewards);
        assert!(balance::value(&pool.staked_tokens) >= stake.amount, EInsufficientRewards);

        // Mark this stake as claimed to prevent double claims
        let stake_mut = vector::borrow_mut(user_stakes, stake_index);
        stake_mut.claimed = true;
        pool.total_rewards_distributed = pool.total_rewards_distributed + reward;

        // Split balances for principal and rewards from pool
        let mut principal_balance = balance::split(&mut pool.staked_tokens, stake.amount);
        let reward_balance = balance::split(&mut pool.reward_pool, reward);

        // Combine principal and rewards for payout
        balance::join(&mut principal_balance, reward_balance);
        let payout_coin = coin::from_balance(principal_balance, ctx);

        // Emit event for stake claimed
        event::emit(StakeClaimed {
            staker,
            stake_id,
            principal: stake.amount,
            reward,
            total_claimed: stake.amount + reward
        });

        payout_coin
    }


    // Emergency unstake allows unstaking before maturity, but forfeits rewards
    public fun emergency_unstake(
        pool: &mut StakingPool,
        stake_id: u64,
        ctx: &mut TxContext
    ): Coin<NIRANJAN_TOKEN> {
        let staker = tx_context::sender(ctx);
        assert!(table::contains(&pool.stakes, staker), EStakeNotFound);

        // Find stake and ensure it was not claimed previously
        let user_stakes = table::borrow_mut(&mut pool.stakes, staker);
        let (stake_index, stake) = find_stake_by_id(user_stakes, stake_id);
        assert!(!stake.claimed, EStakeNotFound);

        // Mark stake as claimed to prevent reuse
        let stake_mut = vector::borrow_mut(user_stakes, stake_index);
        stake_mut.claimed = true;

        // Ensure sufficient tokens to pay back only principal
        assert!(balance::value(&pool.staked_tokens) >= stake.amount, EInsufficientRewards);
        let principal_balance = balance::split(&mut pool.staked_tokens, stake.amount);
        let payout_coin = coin::from_balance(principal_balance, ctx);

        // Emit event showing emergency unstake without rewards
        event::emit(StakeClaimed {
            staker,
            stake_id,
            principal: stake.amount,
            reward: 0,
            total_claimed: stake.amount
        });

        payout_coin
    }


    // Add rewards to reward pool; only callable by pool owner or admin
    public fun add_rewards(pool: &mut StakingPool, reward_coin: Coin<NIRANJAN_TOKEN>, ctx: &TxContext) {
        let sender = tx_context::sender(ctx);
        assert_admin_or_owner(pool, sender);

        // Convert received coin to balance and add to reward pool balance
        let amount = coin::value(&reward_coin);
        let reward_balance = coin::into_balance(reward_coin);
        balance::join(&mut pool.reward_pool, reward_balance);

        // Emit event reflecting addition of new rewards
        let new_total = balance::value(&pool.reward_pool);
        event::emit(RewardsAdded { amount, new_total });
    }


    // Get all stakes for a user; returns empty vector if none exists
    public fun get_user_stakes(pool: &StakingPool, user: address): vector<Stake> {
        if (table::contains(&pool.stakes, user)) {
            *table::borrow(&pool.stakes, user)
        } else {
            vector::empty<Stake>()
        }
    }


    // Get overall pool statistics: total staked, rewards distributed, balances, stake count, paused state
    public fun get_pool_stats(pool: &StakingPool): (u64, u64, u64, u64, u64, bool) {
        (
            pool.total_staked,
            pool.total_rewards_distributed,
            balance::value(&pool.reward_pool),
            balance::value(&pool.staked_tokens),
            pool.next_stake_id - 1,
            pool.paused
        )
    }


    // Calculate potential reward for an amount over the given period in days
    public fun calculate_potential_reward(amount: u64, period_days: u64): u64 {
        let apy = get_apy_for_period(period_days);
        calculate_reward(amount, apy, period_days * SECONDS_IN_DAY)
    }


    // Get APY (basis points) for supported staking periods; 0 if unsupported
    fun get_apy_for_period(period_days: u64): u64 {
        if (period_days == PERIOD_30_DAYS) { APY_30_DAYS }
        else if (period_days == PERIOD_90_DAYS) { APY_90_DAYS }
        else if (period_days == PERIOD_180_DAYS) { APY_180_DAYS }
        else if (period_days == PERIOD_365_DAYS) { APY_365_DAYS }
        else { 0 }
    }


    // Calculate reward based on amount, APY (bp), and duration in seconds
    fun calculate_reward(amount: u64, apy_bp: u64, duration_seconds: u64): u64 {
        let annual_seconds = 365 * SECONDS_IN_DAY;
        (amount * apy_bp * duration_seconds) / (10000 * annual_seconds)
    }


    // Find stake by ID within a user's list of stakes; returns index and stake, aborts if not found or claimed
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
}
