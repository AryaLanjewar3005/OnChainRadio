module radio_addrx::OnChainRadio {
    use std::string::Sting;
    use std::simple_map::{SimpleMap,Self};
    use std::timestamp;

    struct Artist_work has key {
        artist_name: String,
        collection: SimpleMap<u64,Collection>

    }
    struct Collection has store, copy, drop {
        collectionType : String,
        collectionName : String,
        artist_address : address,
        artist_public_key : u64,
        current_timestamp : String,
        streaming_timestamp : String,
        ipfs_hash : String,
        songs : SimpleMap<u64, Song> 
    }
    
    // creates the artist_work resource 
    public entry fun create_artist_work(account : &signer, name : String) {
        let artist_work = Artist_work {
            artist_name : name,
            collection : simple_map::create()
        };
        move_to(account, artist_work);
    }
    // creates collection and stores it in artist_work resource
    public entry fun create_collection (account : &signer, collection_type: String, artist_public_key : u64,collection_name : String, streaming_timestamp: String, ipfs_hash: String) acquires Artist_work {
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global_mut<Artist_work>(signer_address);

        let newCollection = Collection {
            collectionType : collection_type,
            collectionName : collection_name,
            artist_address : signer_address,
            artist_public_key : artist_public_key,
            current_timestamp : timestamp::now_seconds(),
            streaming_timestamp : streaming_timestamp,
            ipfs_hash : ipfs_hash,
            songs : simple_map::create()

        }
        //collection map under artist_work (WIP : nonce mapping)
        simple_map::add(&mut artist_work.collection,1 , newCollection);

    }
}