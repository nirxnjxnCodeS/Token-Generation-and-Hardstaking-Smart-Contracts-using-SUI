module niranjan_token::niranjan_token {
    use std::option;
    use sui::coin::{Self as coin, TreasuryCap, Coin};
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::url::Url;

    // Marker type for your token
    public struct NIRANJAN_TOKEN has drop {}

    // Initialize currency at publish
    fun init(witness: NIRANJAN_TOKEN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<NIRANJAN_TOKEN>(
            witness,
            9,                          // decimals
            b"NIRX",                    // symbol
            b"Niranjan Token",          // name
            b"Token for demos on Sui Testnet",
            option::none<Url>(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }

    // Mint tokens to a recipient
    public fun mint(
        cap: &mut TreasuryCap<NIRANJAN_TOKEN>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let c: Coin<NIRANJAN_TOKEN> = coin::mint<NIRANJAN_TOKEN>(cap, amount, ctx);
        transfer::public_transfer(c, recipient);
    }

    // Burn tokens
    public fun burn(cap: &mut TreasuryCap<NIRANJAN_TOKEN>, c: Coin<NIRANJAN_TOKEN>): u64 {
        coin::burn<NIRANJAN_TOKEN>(cap, c)
    }
}
