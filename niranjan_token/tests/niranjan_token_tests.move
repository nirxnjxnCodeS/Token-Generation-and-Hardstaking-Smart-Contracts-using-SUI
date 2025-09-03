#[test_only]
module niranjan_token::niranjan_token_tests {
    use sui::coin::{Self as coin, TreasuryCap, Coin};
    use sui::test_scenario as ts;
    use sui::transfer;
    use niranjan_token::niranjan_token;

    /// Mint 100 and burn it.
    #[test]
    fun test_mint_and_burn() {
        // This address is the "publisher" for this test
        let mut sc = ts::begin(@0xA);

        // Take the TreasuryCap that 'init' transferred to @0xA at publish
        let mut cap = ts::take_from_address<TreasuryCap<niranjan_token::NIRANJAN_TOKEN>>(
            &mut sc, @0xA
        );

        // Only borrow ctx AFTER taking objects to avoid borrow conflicts
        let ctx = ts::ctx(&mut sc);

        // Mint and check
        let c: Coin<niranjan_token::NIRANJAN_TOKEN> =
            coin::mint<niranjan_token::NIRANJAN_TOKEN>(&mut cap, 100, ctx);
        assert!(coin::value(&c) == 100, 0);

        // Burn and check
        let burned = niranjan_token::burn(&mut cap, c);
        assert!(burned == 100, 1);

        // Consume the TreasuryCap so the test can end cleanly
        transfer::public_transfer(cap, @0xA);
        ts::end(sc);
    }

    /// Two mints, join, burn.
    #[test]
    fun test_multiple_mints_and_join() {
        let mut sc = ts::begin(@0xB);
        let mut cap = ts::take_from_address<TreasuryCap<niranjan_token::NIRANJAN_TOKEN>>(
            &mut sc, @0xB
        );
        let ctx = ts::ctx(&mut sc);

        let mut c1 = coin::mint<niranjan_token::NIRANJAN_TOKEN>(&mut cap, 500, ctx);
        let c2 = coin::mint<niranjan_token::NIRANJAN_TOKEN>(&mut cap, 250, ctx);

        coin::join(&mut c1, c2);
        assert!(coin::value(&c1) == 750, 2);

        let burned = niranjan_token::burn(&mut cap, c1);
        assert!(burned == 750, 3);

        transfer::public_transfer(cap, @0xB);
        ts::end(sc);
    }

    /// Use your module's `mint` API that sends to a recipient address.
    #[test]
    fun test_module_mint_to_recipient() {
        let mut sc = ts::begin(@0xC);
        let mut cap = ts::take_from_address<TreasuryCap<niranjan_token::NIRANJAN_TOKEN>>(
            &mut sc, @0xC
        );
        let ctx = ts::ctx(&mut sc);

        // Mint 42 directly to @0xD using your API
        niranjan_token::mint(&mut cap, 42, @0xD, ctx);

        // Grab the coin from the recipient and verify
        let received: Coin<niranjan_token::NIRANJAN_TOKEN> =
            ts::take_from_address<Coin<niranjan_token::NIRANJAN_TOKEN>>(&mut sc, @0xD);
        assert!(coin::value(&received) == 42, 4);

        // Clean up the received coin as part of the test
        let _ = niranjan_token::burn(&mut cap, received);

        transfer::public_transfer(cap, @0xC);
        ts::end(sc);
    }
}
