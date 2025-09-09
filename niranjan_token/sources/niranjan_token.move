module niranjan_token::niranjan_token {
    use sui::coin::{Self as coin, Coin};
    use sui::url::Url;
    use sui::event;

    /// Error codes
    const ENotOwner: u64 = 100;
    const EMaxAdminsReached: u64 = 101;

    /// Constants
    const MAX_ADMINS: u64 = 2;
    const TOTAL_SUPPLY: u64 = 1_000_000_000_000_000_000; // 1 billion with 9 decimals

    /// Marker type for the token
    public struct NIRANJAN_TOKEN has drop {}

    /// Owner capability - only one exists
    public struct OwnerCap has key, store {
        id: UID,
        owner: address,
    }

    /// Admin capability - maximum 2 can exist
    public struct AdminCap has key, store {
        id: UID,
        admin: address,
    }
    /// Supply object to track total supply after treasury is destroyed
    public struct Supply has key, store {
        id: UID,
        total_supply: u64,
        current_admins: u64,
    }

    /// Events
    public struct TokenMinted has copy, drop {
        recipient: address,
        amount: u64,
    }

    public struct AdminDelegated has copy, drop {
        owner: address,
        new_admin: address,
        total_admins: u64,
    }

    public struct SupplyCreated has copy, drop {
        total_supply: u64,
    }

    /// Initialize the token at publish
    fun init(witness: NIRANJAN_TOKEN, ctx: &mut TxContext) {
        // Create currency
        let (mut treasury, metadata) = coin::create_currency<NIRANJAN_TOKEN>(
            witness,
            9,                   // decimals
            b"NIRX",             // symbol
            b"Niranjan Token",   // name
            b"Token for demos on Sui Testnet", // description
            option::none<Url>(), // icon URL
            ctx
        );

        let owner = tx_context::sender(ctx);

        // Mint initial supply of 1 billion tokens
        let initial_coins: Coin<NIRANJAN_TOKEN> = coin::mint<NIRANJAN_TOKEN>(&mut treasury, TOTAL_SUPPLY, ctx);

        // Transfer initial supply to owner
        transfer::public_transfer(initial_coins, owner);

        // Emit token minted event
        event::emit(TokenMinted { 
            recipient: owner, 
            amount: TOTAL_SUPPLY 
        });

        // Freeze metadata so it's immutable
        transfer::public_freeze_object(metadata);

        // Create and transfer OwnerCap to owner
        let owner_cap = OwnerCap { 
            id: object::new(ctx), 
            owner 
        };
        transfer::public_transfer(owner_cap, owner);

        // Freeze the treasury cap to prevent any further minting or burning
        transfer::public_freeze_object(treasury);
        
        // Create our custom Supply tracker for governance
        let supply = Supply {
            id: object::new(ctx),
            total_supply: TOTAL_SUPPLY,
            current_admins: 0,
        };

        // Transfer Supply object to owner
        transfer::public_transfer(supply, owner);

        // Emit supply created event
        event::emit(SupplyCreated { 
            total_supply: TOTAL_SUPPLY 
        });

    }

    /// Delegate admin capability (only callable by owner, max 2 admins)
    public fun delegate_admin(
        owner_cap: &OwnerCap, 
        supply: &mut Supply,
        new_admin: address, 
        ctx: &mut tx_context::TxContext
    ) {
        // Verify caller is the owner
        assert!(tx_context::sender(ctx) == owner_cap.owner, ENotOwner);
        
        // Check if max admins limit reached
        assert!(supply.current_admins < MAX_ADMINS, EMaxAdminsReached);

        // Create and transfer admin capability
        let admin_cap = AdminCap { 
            id: object::new(ctx), 
            admin: new_admin 
        };
        transfer::public_transfer(admin_cap, new_admin);

        // Increment admin count
        supply.current_admins = supply.current_admins + 1;

        // Emit admin delegated event
        event::emit(AdminDelegated { 
            owner: owner_cap.owner, 
            new_admin,
            total_admins: supply.current_admins
        });
    }

    /// View function: Get total supply
    public fun get_total_supply(supply: &Supply): u64 {
        supply.total_supply
    }

    /// View function: Get current number of admins
    public fun get_admin_count(supply: &Supply): u64 {
        supply.current_admins
    }

    /// View function: Check if caller is owner
    public fun is_owner(owner_cap: &OwnerCap, caller: address): bool {
        owner_cap.owner == caller
    }

    /// View function: Check if caller is admin
    public fun is_admin(admin_cap: &AdminCap, caller: address): bool {
        admin_cap.admin == caller
    }

    /// View function: Check balance of a coin
    public fun balance_of(coin: &Coin<NIRANJAN_TOKEN>): u64 {
        coin::value(coin)
    }

    /// View function: Get owner address from OwnerCap
    public fun get_owner(owner_cap: &OwnerCap): address {
        owner_cap.owner
    }

    /// View function: Get admin address from AdminCap
    public fun get_admin(admin_cap: &AdminCap): address {
        admin_cap.admin
    }
    public fun change_owner(owner_cap: &mut OwnerCap, new_owner: address, ctx: &mut tx_context::TxContext) {
    // Verify the caller is the current owner
    assert!(tx_context::sender(ctx) == owner_cap.owner, 1);

    // Update owner
    owner_cap.owner = new_owner;
}

}


/*
Check coin balance
sui client object 0xfbea0dbc15fbc9551a4cfd5f5a0be56e5a4f79daad60c06dd1a21192c21543b6

# Check Supply object ( total_supply: 1000000000000000000, current_admins:0
sui client object 0xc97272d4f36498cec51d6eae7cf629154ec435c58ad2d9220b0922e7a1fa5bd1

# Check Owner capability
sui client object 0xf13a46595ad69591b378c1a1b46d584af9f6ed22e345409f3f35385fc2574b00

# Get total supply
sui client call \
  --package 0x1e6a574391637cdc2e607f9f32f2b0f6402603c0d08507c6d1434d5c49757416 \
  --module niranjan_token \
  --function get_total_supply \
  --args 0xc97272d4f36498cec51d6eae7cf629154ec435c58ad2d9220b0922e7a1fa5bd1 \
  --gas-budget 10000000

# Check current admin count (0)
sui client call \
  --package 0x1e6a574391637cdc2e607f9f32f2b0f6402603c0d08507c6d1434d5c49757416 \
  --module niranjan_token \
  --function get_admin_count \
  --args 0xc97272d4f36498cec51d6eae7cf629154ec435c58ad2d9220b0922e7a1fa5bd1 \
  --gas-budget 10000000


# Test balance_of function
sui client call \
 --package 0x1e6a574391637cdc2e607f9f32f2b0f6402603c0d08507c6d1434d5c49757416 \
 --module niranjan_token \
 --function balance_of \
 --args 0xfbea0dbc15fbc9551a4cfd5f5a0be56e5a4f79daad60c06dd1a21192c21543b6 \
 --gas-budget 10000000


*/
