module radio_addrx::OnChainRadio {
    use std::string::{String};
    use std::simple_map::{SimpleMap,Self};
    use aptos_framework::timestamp;
    use std::signer; 
    // use std::from_bcs;
    // use std::aptos_hash; 
    use std::account;
    use std::error;
    use std::vector;
    use 0x1::coin;
    use 0x1::aptos_coin::AptosCoin; 
    use 0x1::aptos_account;
    use aptos_framework::event;
    // use std::debug;
    // use aptos_framework::aptos_token;

    // define errors
    const Account_Not_Found:u64 =404;
    const Collection_Not_Found:u64=808;
    const E_NOT_ENOUGH_COINS:u64 = 202;
    const Artist_Not_Found:u64=101;


    struct Artist_work has key ,store{
        artist_name: String,
        Nonce:u64,
        Collections:SimpleMap<String,Collection>,
        Monitize_collections:SimpleMap<String,Monitize_collection>,
        Signature_Details:SimpleMap<String,SignatureDetails>,
        HashIds: vector<String>,
        artist_resource_event: event::EventHandle<Collection>,

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
    

    // call only one time
    // creates the artist_work resource 
    public entry fun create_artist_work(account : &signer, name : String)  {
        let artist_work = Artist_work {
            artist_name : name,
            Nonce:1,
            Collections : simple_map::create(),
            Monitize_collections:simple_map::create(),
            Signature_Details:simple_map::create(),
            HashIds:vector::empty<String>(),
            artist_resource_event:account::new_event_handle<Collection>(account),
            

        };
        // debug::print(&artist_work);
        move_to(account, artist_work);
    }
    // creates collection and stores it in artist_work resource

    public entry fun create_collection (account : &signer,collection_type: String,collection_name : String, streaming_timestamp: u64, ipfs_hash: String)acquires Artist_work {
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

        let songHashId=ipfs_hash;


        vector::push_back(&mut artist_work.HashIds , songHashId);
        simple_map::add(&mut artist_work.Collections,songHashId , newCollection);

        //update nonce for artist account
        artist_work.Nonce=artist_work.Nonce+1;

        // event
        event::emit_event<Collection>(
            &mut borrow_global_mut<Artist_work>(signer_address).artist_resource_event,
            newCollection,
        );

    }
    // get all songhashIds vector by account
    #[view]
    public fun  GetHashIds(account:&signer):vector<String> acquires Artist_work {
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.HashIds
    }

    // get nonce of account
    #[view]
    public fun GetNonce(account:&signer) :u64 acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.Nonce
    }
    
    // get collection info by songHashId
    #[view]
    public fun getCollectionInfo(account:&signer,_songHashId:String):SimpleMap<String,Collection> acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        artist_work.Collections

    }

    // get monitize info by songHashId
    #[view]
    public fun getMonitizeInfo(account:&signer,_songHashId:String):SimpleMap<String,Monitize_collection>  acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        artist_work.Monitize_collections

    }

     // get Signature  info by songHashId
     #[view]
    public fun getSignatureInfo(account:&signer,_songHashId:String):SimpleMap<String,SignatureDetails>  acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        artist_work.Signature_Details

    }


    struct Monitize_collection has key,copy,drop,store{
        IsEKycVerified:bool,
        NoOfMaxCopies:u64,
        NoOfCopyReleased:u64,
        PriceOfCopy:u64,
        CertificateActivated:bool,
        Royality:u64,   // royality in %
        
        CopyExpiryTimestamp:u64,
    }

    struct SignatureDetails has key,store,drop,copy{
        Ceritificate_IPFS_Address:String,
        Certifiate_Signature:vector<u8>,
    }


    public entry fun Monitize_work(account:&signer,songHashId:String, isEKycVerifiedA: bool, noOfMaxCopiesA : u64,noOfCopyReleasedA : u64 ,priceOfCopyA : u64, certificateActivatedA : bool, royalityA : u64, copyExpiryTimestampA : u64 ) acquires Artist_work{        // check account with given hashId
            let signer_address = signer::address_of(account);
            // check account exist or not
            if (!exists<Artist_work>(signer_address)){
                error::not_found(Account_Not_Found);
            };

            let artist_work = borrow_global_mut<Artist_work>(signer_address);
            // check wheather collections exist or not for given songHashId
            if (!simple_map::contains_key(&mut artist_work.Collections,&songHashId)){
                error::not_found(Collection_Not_Found);
            };
            let monitize = Monitize_collection {
                IsEKycVerified : isEKycVerifiedA,
                NoOfMaxCopies : noOfMaxCopiesA,
                NoOfCopyReleased : noOfCopyReleasedA,
                PriceOfCopy : priceOfCopyA,
                CertificateActivated : certificateActivatedA,
                Royality : royalityA,
                CopyExpiryTimestamp : copyExpiryTimestampA
            };


            // push/update monitize info in artist resources
            simple_map::add(&mut artist_work.Monitize_collections,songHashId , monitize);

            // push signature and hash in resource
            // simple_map::add(&mut artist_work.Signature_Details,songHashId , signatuedetails);

        }
    
    

    // tip send by client to artist account
    public entry fun Donate(account:&signer,amount:u64,_songhash:String,artist_address:address){
        // must have coin more than amount in account
        let from_acc_balance:u64 = coin::balance<AptosCoin>(signer::address_of(account));
                // check account exist or not
        if (!exists<Artist_work>(artist_address)){
            error::not_found(Artist_Not_Found);
        };


        if(from_acc_balance<=amount){
            error::not_found(E_NOT_ENOUGH_COINS);
        };

        // //transfer coin from client to artist
        aptos_account::transfer(account,artist_address,amount); 

    }
    public entry fun Broadcast(account: &signer,songHashId: String, certificateIPFSAddress : String, signature: vector<u8>)acquires Artist_work {
        let signer_address = signer::address_of(account);
            // check account exist or not
            if (!exists<Artist_work>(signer_address)){
                error::not_found(Account_Not_Found);
            };

            let artist_work = borrow_global_mut<Artist_work>(signer_address); 

            let signatureDetails = SignatureDetails {
                Ceritificate_IPFS_Address : certificateIPFSAddress,
                Certifiate_Signature : signature
            };
            simple_map::add(&mut artist_work.Signature_Details,songHashId , signatureDetails);

    }

    struct ContentInfo has copy,drop,store{
        Artist_address:address,
        Artist_signature:vector<u8>,
        CopyNumber:u64,
        Content_IPFS_address:String,
        Ceritificate_By_artist_IPFS_Address:String,
        Ceritificate_By_client_IPFS_Address:String,
        Timestamp:u64,
        Client_address:address,
        Client_signature:vector<u8>,
        Price:u64,
        Platform_name:String,
    }

    struct Client_resource has key,store{
        Collections:SimpleMap<String,ContentInfo>,
        client_resource_event:event::EventHandle<ContentInfo>,
    }
    
     // call only one time
    // creates the client resource 
    public entry fun create_client_resource(account : &signer)  {
        let client_resource = Client_resource {
            Collections:simple_map::create(),
            client_resource_event:account::new_event_handle<ContentInfo>(account),

        };

        move_to(account, client_resource);
    }


    // purchase copy of song after streaming

    public entry fun Purchase(account:&signer,songhashid:String,artist_address:address) acquires Artist_work, Client_resource{
        //1. check no of copies avilable or not
        let client_address = signer::address_of(account);
        
        let client_resource = borrow_global_mut<Client_resource>(client_address);
        let artist_work = borrow_global_mut<Artist_work>(artist_address);
        let monitizationDetails = simple_map::borrow(&mut artist_work.Monitize_collections,&songhashid);
        let price = monitizationDetails.PriceOfCopy;
        aptos_account::transfer(account,artist_address,price);
        monitizationDetails.PriceOfCopy = monitizationDetails.PriceOfCopy - 1;


        // 2. verify signature of artist
        // 3. an account must purchase only one copy
        //4. create resource for user if not avilable
        //5. push signature and hash of user and songhashid to user resources
        // 4. create nft including all info about content and move to user account
        // 6.  
        //4. transfer aptos coint to artist account

    }


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
        create_artist_work(&artist,name);
        let nonce = GetNonce(&artist);
        assert!(nonce == 1, 0);
        print(&nonce);
        print(&name);
        // create_collection(&artist,collection_type,collection_name,streaming_timestamp,ipfs_hash);
        // let collection:SimpleMap<String,Collection> =GetCollectionInfo(&artist,ipfs_hash);
        // let nonce=GetNonce(&artist);
        // assert!(GetNonce(&artist)==6,1);
        // debug::print(&info)

        // print(artist.authentication_key)

    }

}

