 module radio_addrx::OnChainRadioCoin{
    //article: https://blocksecteam.medium.com/security-practices-in-move-development-2-aptos-coin-abe7ab7509fb
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_std::type_info;
    use std::string::{utf8, String};
    use std::signer;


    struct RadioCoin{}
    
    struct CapStore has key{
        mint_cap: coin::MintCapability<RadioCoin>,
        freeze_cap: coin::FreezeCapability<RadioCoin>,
        burn_cap: coin::BurnCapability<RadioCoin>
    }

    struct RadioEventStore has key{
        event_handle: event::EventHandle<String>,
    }

    //there is an init_module function, which is used to initialize the module and will only be called once when the module is published on the chain.
    fun init_module(account: &signer){
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<RadioCoin>(account, utf8(b"RadioCoin"), utf8(b"RadioCoin"), 6, true);
        move_to(account, CapStore{mint_cap: mint_cap, freeze_cap: freeze_cap, burn_cap: burn_cap});
    }

    public entry fun register(account: &signer){
        let address_ = signer::address_of(account);
        if(!coin::is_account_registered<RadioCoin>(address_)){
            coin::register<RadioCoin>(account);
        };
        if(!exists<RadioEventStore>(address_)){
            move_to(account, RadioEventStore{event_handle: account::new_event_handle(account)});
        };
    }

    fun emit_event(account: address, msg: String) acquires RadioEventStore{
        event::emit_event<String>(&mut borrow_global_mut<RadioEventStore>(account).event_handle, msg);
    }
    //only admins can mint coins
    public entry fun mint_coin(cap_owner: &signer, to_address: address, amount: u64) acquires CapStore, RadioEventStore{
        let mint_cap = &borrow_global<CapStore>(signer::address_of(cap_owner)).mint_cap;
        let mint_coin = coin::mint<RadioCoin>(amount, mint_cap);
        coin::deposit<RadioCoin>(to_address, mint_coin);
        emit_event(to_address, utf8(b"minted Radio coin"));
    }

    //any user can invoke the burn_coin function
    public entry fun burn_coin(account: &signer, amount: u64) acquires CapStore, RadioEventStore{
        let owner_address = type_info::account_address(&type_info::type_of<RadioCoin>());
        let burn_cap = &borrow_global<CapStore>(owner_address).burn_cap;
        let burn_coin = coin::withdraw<RadioCoin>(account, amount);
        coin::burn<RadioCoin>(burn_coin, burn_cap);
        emit_event(signer::address_of(account), utf8(b"burned RadioCoin"));
    }

    public entry fun freeze_self(account: &signer) acquires CapStore, RadioEventStore{
        let owner_address = type_info::account_address(&type_info::type_of<RadioCoin>());
        let freeze_cap = &borrow_global<CapStore>(owner_address).freeze_cap;
        let freeze_address = signer::address_of(account);
        coin::freeze_coin_store<RadioCoin>(freeze_address, freeze_cap);
        emit_event(freeze_address, utf8(b"freezed self"));
    }

    public entry fun emergency_freeze(cap_owner: &signer, freeze_address: address) acquires CapStore, RadioEventStore{
        let owner_address = signer::address_of(cap_owner);
        let freeze_cap = &borrow_global<CapStore>(owner_address).freeze_cap;
        coin::freeze_coin_store<RadioCoin>(freeze_address, freeze_cap);
        emit_event(freeze_address, utf8(b"emergency freezed"));
    }

    public entry fun unfreeze(cap_owner: &signer, unfreeze_address: address) acquires CapStore, RadioEventStore{
        let owner_address = signer::address_of(cap_owner);
        let freeze_cap = &borrow_global<CapStore>(owner_address).freeze_cap;
        coin::unfreeze_coin_store<RadioCoin>(unfreeze_address, freeze_cap);
        emit_event(unfreeze_address, utf8(b"unfreezed"));
    }

    /*
    opration on Radiocoin
    1. coin::transfer<RadioCoin>(from:&signer,to:address,amount:u64)
    #[view]
    2. coin::balance<RadioCoin>(owner:address):u64
    3. coin::is_coin_initialized<RadioCoin>(): bool
    4. coin::is_coin_store_frozen<RadioCoin>(account_addr: address): bool
    5. coin::is_account_registered<RadioCoin>(account_addr: address): bool
    6. coin::supply<RadioCoin>(): Option<u128> 

    */ 


    
}