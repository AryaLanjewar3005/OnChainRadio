module radio_addrx::OnChainRadio {
    use std::string::{String,utf8};
    // use std::simple_map::{SimpleMap,Self};
    use std::timestamp;
    use std::signer; 
    // use std::hash; 
    use std::account;
    // use std::debug;
    use std::vector;
    // use std::Aptos::any;

    struct Artist_work has key ,store,drop{
        artist_name: String,
        Nonce:u64,
        //key==local nonce,value=collection
        Collections: vector<Collection>

    }
    struct Collection has store,copy, drop,key {
        collectionType : String,
        collectionName : String,
        artist_address : address,
        artist_Authentication_key : vector<u8>,
        current_timestamp : u64,
        streaming_timestamp : u64,
        collection_ipfs_hash : String,
    }
    
    // call only one time
    // creates the artist_work resource 
    fun create_artist_work(account : &signer, name : String)  {
        let artist_work = Artist_work {
            artist_name : name,
            Nonce:1,
            Collections : vector::empty<Collection>()
        };
        // debug::print(&artist_work);
        move_to(account, artist_work);
    }
    // creates collection and stores it in artist_work resource
    public entry fun create_collection (account : &signer,name:String,collection_type: String,collection_name : String, streaming_timestamp: u64, ipfs_hash: String) acquires Artist_work {
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global_mut<Artist_work>(signer_address);
        if (artist_work.Nonce==0){
            // create the artist_work resource
            create_artist_work(account,name);

        };
        let signer_authentication_key=account::get_authentication_key(signer_address);

        let newCollection = Collection {
            collectionType : collection_type,
            collectionName : collection_name,
            artist_address : signer_address,
            artist_Authentication_key : signer_authentication_key,
            current_timestamp : timestamp::now_seconds(),
            streaming_timestamp : streaming_timestamp,
            collection_ipfs_hash : ipfs_hash,

        };

        //collection map under artist_work (WIP : nonce mapping)
        vector::push_back(&mut artist_work.Collections , newCollection);

        //update nonce for artist account
        artist_work.Nonce=artist_work.Nonce+1;

        // map collection in globally




    }

    // get all collections vector by account
    public fun GetCollectionsInfo(account:&signer):vector<Collection> acquires Artist_work {
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.Collections
    }

    // get nonce of account
    public fun GetNonce(account:&signer) :u64 acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.Nonce
    }
    
    // get collection info by songHash
    // public fun getCollectionInfo(account:&signer):Collection acquires Artist_work{

    // }

       #[test(artist = @0x123,user1=@0x456,user2=@678)]
    public entry fun test_flow(artist: signer,user1:signer,user2:signer)  acquires Artist_work
    {
        account::create_account_for_test(signer::address_of(&artist));
        account::create_account_for_test(signer::address_of(&user1));
        account::create_account_for_test(signer::address_of(&user2));

        // create_artist_work(&artist,utf8(b"Welcome to Aptos anand by Example"));
        let name:String = utf8(b"arjit singh");
        let collection_type:String = utf8(b"arjit singh");
        let collection_name:String = utf8(b"arjit singh");
        let ipfs_hash:String = utf8(b"arjit singh");
        let streaming_timestamp: u64=timestamp::now_seconds();
        create_collection(&artist,name,collection_type,collection_name,streaming_timestamp,ipfs_hash);
        // let info=GetCollectionInfo(&artist);
        // let nonce=GetNonce(&artist);
        // assert!(GetNonce(&artist)==6,1);
        // debug::print(&info)

        // print(artist.authentication_key)

    }
}