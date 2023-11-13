module radio_addrx::OnChainRadio {
    use std::string::{String,utf8};
    use std::simple_map::{SimpleMap,Self};
    use std::timestamp;
    use std::signer; 
    use std::from_bcs;
    use std::aptos_hash; 
    use std::account;
    use std::option;
    use std::error;
    // use std::debug;
    use std::vector;
    use std::ed25519;
    // use std::Aptos::any;
    const Account_Not_Found:u64 =404;

    struct Artist_work has key ,store,drop{
        artist_name: String,
        Nonce:u64,
        Collections:SimpleMap<String,Collection>,
        Monitize_collections:SimpleMap<String,Monitize_collection>,
        Signature_Details:SimpleMap<String,SignatureDetails>,
        HashIds: vector<String>,

    }
    struct Collection has copy, drop,key,store {
        collectionType : String,
        collectionName : String,
        artist_address : address,
        artist_Authentication_key : vector<u8>,
        current_timestamp : u64,
        streaming_timestamp : u64,
        collection_ipfs_hash : String,
    }
    
    struct GlobalInfo has store,key,drop{
        TotalContent:u64,
        SongMap_Total_To_CollectionInfo:SimpleMap<String,CollectionInfo>,
        
    }

    // call only one time
    // creates the artist_work resource 
    fun create_artist_work(account : &signer, name : String)  {
        let artist_work = Artist_work {
            artist_name : name,
            Nonce:1,
            Collections : simple_map::create(),
            Monitize_collections:simple_map::create(),
            Signature_Details:simple_map::create(),
            HashIds:vector::empty<String>(),
            

        };
        // debug::print(&artist_work);
        move_to(account, artist_work);
    }
    // creates collection and stores it in artist_work resource
    // return songhashID for this collection
    public  fun create_collection (account : &signer,name:String,collection_type: String,collection_name : String, streaming_timestamp: u64, ipfs_hash: String):String acquires Artist_work {
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global_mut<Artist_work>(signer_address);
        if (!exists<Artist_work>(signer_address)){
            error::not_found(Account_Not_Found);
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

        // get global counter
        // let counter=borrow_global_mut<GlobalInfo>().TotalContent;
        let counter=1;
        // convert into bytes
        let x:vector<u8> = from_bcs::to_bytes(vector<u8>[counter]);
        // Calculate songhashid
        let hashId=aptos_hash::keccak256(x);
        let songHashId=from_bcs::to_string(hashId);

        //collection map under artist_work (WIP : nonce mapping)
        // vector::push_back(&mut artist_work.Collections , newCollection);
        simple_map::add(&mut artist_work.Collections,songHashId , newCollection);

        // update global counter

        // counter=counter+1;

        //update nonce for artist account
        artist_work.Nonce=artist_work.Nonce+1;
        return songHashId

    }

    // get artist work by account

    // public fun GetArtistWork(account:&signer):&Artist_work acquires Artist_work{
    //     let signer_address = signer::address_of(account);
    //     let artist_work_ref = borrow_global<Artist_work>(signer_address);
    //     let artist_work = copy artist_work_ref;
    //     artist_work
    // }

    // get all songhashIds vector by account
    public fun GetHashIds(account:&signer):vector<String> acquires Artist_work {
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.HashIds
    }

    // get nonce of account
    public fun GetNonce(account:&signer) :u64 acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.Nonce
    }
    
    // // get collection info by songHashId
    // public fun getCollectionInfo(account:&signer,songHashId:String):Collection acquires Artist_work{
    //     let signer_address = signer::address_of(account);
    //     let artist_work = borrow_global<Artist_work>(signer_address);
    //     simple_map::borrow(&mut artist_work.Collections,&songHashId)

    // }

    // // get monitize info by songHashId
    // public fun getMonitizeInfo(account:&signer,songHashId:String):Monitize_collection acquires Artist_work{
    //     let signer_address = signer::address_of(account);
    //     let artist_work = borrow_global<Artist_work>(signer_address);
    //     simple_map::borrow(&mut artist_work.Monitize_collections,&songHashId)

    // }

    //  // get Signature  info by songHashId
    // public fun getSignatureInfo(account:&signer,songHashId:String):SignatureDetails acquires Artist_work{
    //     let signer_address = signer::address_of(account);
    //     let artist_work = borrow_global<Artist_work>(signer_address);
    //     simple_map::borrow(&mut artist_work.Signature_Details,&songHashId)

    // }


    struct Monitize_collection has key,copy,drop,store{
        IsEKycVerified:bool,
        NoOfMaxCopies:u64,
        NoOfCopyReleased:u64,
        PriceOfCopy:u64,
        CertificateActivated:bool,
        Royality:u64,   // royality in %
        Ceritificate_IPFS_Address:String,
        CopyExpiryTimestamp:u64,
    }

    struct SignatureDetails has key,store,drop{
        Ceritificate_Hash:vector<u8>,
        Certifiate_Signature:vector<u8>,
    }

    // for store on blockchain
    struct CollectionInfo has key,store,drop{
        ArtistWork:Artist_work,
        Collections:Collection,
        Monitize:Monitize_collection,
        signature:SignatureDetails,

    }

    public fun Monitize_work(account:&signer,songHashId:String, monitize:Monitize_collection,signatuedetails:SignatureDetails) acquires Artist_work{
        //check account with given hashId
        let signer_address = signer::address_of(account);
        if (!exists<Artist_work>(signer_address)){
            error::not_found(Account_Not_Found);
        };
        let artist_work = borrow_global_mut<Artist_work>(signer_address);

        // push/update monitize info in resources
        simple_map::add(&mut artist_work.Monitize_collections,songHashId , monitize);

        // verify signature of collection
        // require public key
        // let sucess=ed25519::signature_verify_strict(signatuedetails.Certifiate_Signature,,signatuedetails.Ceritificate_Hash);
        // push signature and hash in resource
        simple_map::add(&mut artist_work.Signature_Details,songHashId , signatuedetails);

        // updata global map with collectionInfo


    }

    // // tip send by client to artise
    // public fun Donate(account:&signer,amount:u64,songhash:String){
    //     // must have coin more than amount in account

    //     //transfer coin from client to artist

    // }

    // // purchase copy of song after streaming

    // // public fun Purchase()


    //////////////////test case///////////////

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