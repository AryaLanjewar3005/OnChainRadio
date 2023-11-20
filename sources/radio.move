module radio_addrx::OnChainRadio {
    use std::string::{String,utf8};
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
    use std::debug::print;
    // use aptos_token::token;

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

    // struct Data has store,copy{
    //     ArtistWork:Artist_work,
   


    // }

    // struct GlobalData has key{
    //     Nonce:u64,
    //     Song:SimpleMap<String,Data>
    // }

    // public entry fun CreateGlobaldatabase(account:&signer){
    //     if(exists<GlobalData>(@radio_addrx)){
    //         // global data base already created
    //     };
    //     // let data=Data{

    //     // }
    //     move_to(account, artist_work);
        
        
    // }

     #[view]
    // get all songhashIds vector by account
    public fun GetHashIds(account:&signer):vector<String> acquires Artist_work {
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.HashIds
    }

     #[view]
    // get nonce of account
    public fun GetNonce(account:&signer) :u64 acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        return artist_work.Nonce
    }
    
     #[view]
    // get collection info by songHashId
    public fun getCollectionInfo(account:&signer,_songHashId:String):SimpleMap<String,Collection> acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        artist_work.Collections

    }

     #[view]
    // get monitize info by songHashId
    public fun getMonitizeInfo(account:&signer,_songHashId:String):SimpleMap<String,Monitize_collection>  acquires Artist_work{
        let signer_address = signer::address_of(account);
        let artist_work = borrow_global<Artist_work>(signer_address);
        artist_work.Monitize_collections

    }

     #[view]
     // get Signature  info by songHashId
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
        Ceritificate_IPFS_Address:String,
        CopyExpiryTimestamp:u64,
    }

    struct SignatureDetails has key,store,drop,copy{
        Ceritificate_Hash:vector<u8>,
        Certifiate_Signature:vector<u8>,
    }


public  fun Monitize_work(account:&signer,songHashId:String, monitize:Monitize_collection,signatuedetails:SignatureDetails) acquires Artist_work{        // check account with given hashId
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

        // push/update monitize info in artist resources
        simple_map::add(&mut artist_work.Monitize_collections,songHashId , monitize);

        // push signature and hash in resource
        simple_map::add(&mut artist_work.Signature_Details,songHashId , signatuedetails);

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

    // public entry fun Purchase(account:&signer,songhashid:String,artist_address:address){

    //    let artist_work = borrow_global<Artist_work>(artist_address);
    //     // check wheather collections exist or not for given songHashId
    //     let price=borrow(&mut artist_work.Monitize_collections,&songhashid).PriceOfCopy;
    //     // aptos_account::transfer(account,artist_address,price); 

    //     // create and transfer nft
        

    // }

    //    fun Create_Nft(source_account: &signer,collection_name:String,description:String,collection_uri:String,token_name:String,token_uri:String) {
    //     // This means that the supply of the token will not be tracked.
    //     let maximum_supply = 0;
    //     // This variable sets if we want to allow mutation for collection description, uri, and maximum.
    //     // Here, we are setting all of them to false, which means that we don't allow mutations to any CollectionData fields.
    //     let mutate_setting = vector<bool>[ false, false, false ];

    //     // Create the nft collection.
    //     token::create_collection(source_account, collection_name, description, collection_uri, maximum_supply, mutate_setting);

    //     // Create a token data id to specify the token to be minted.
    //     let token_data_id = token::create_tokendata(
    //         source_account,
    //         collection_name,
    //         token_name,
    //         string::utf8(b""),
    //         0,
    //         token_uri,
    //         signer::address_of(source_account),
    //         1,
    //         0,
    //         // This variable sets if we want to allow mutation for token maximum, uri, royalty, description, and properties.
    //         // Here we enable mutation for properties by setting the last boolean in the vector to true.
    //         token::create_token_mutability_config(
    //             &vector<bool>[ false, false, false, false, true ]
    //         ),
    //         // We can use property maps to record attributes related to the token.
    //         // In this example, we are using it to record the receiver's address.
    //         // We will mutate this field to record the user's address
    //         // when a user successfully mints a token in the `mint_nft()` function.
    //         vector<String>[string::utf8(b"given_to")],
    //         vector<vector<u8>>[b""],
    //         vector<String>[ string::utf8(b"address") ],
    //     );

    //     // Store the token data id within the module, so we can refer to it later
    //     // when we're minting the NFT and updating its property version.
    //     move_to(source_account, ModuleData {
    //         token_data_id,
    //     });
    // }



    //////////////////test case///////////////

       #[test(artist = @0x123,user1=@0x456,user2=@678)]
    public entry fun test_flow(artist: signer,user1:signer,user2:signer)  acquires Artist_work
    {
        account::create_account_for_test(signer::address_of(&artist));
        account::create_account_for_test(signer::address_of(&user1));
        account::create_account_for_test(signer::address_of(&user2));

        // create_artist_work(&artist,utf8(b"Welcome to Aptos anand by Example"));
        let name:String = utf8(b"arjit singh");
        // let _collection_type:String = utf8(b"arjit singh");
        // let _collection_name:String = utf8(b"arjit singh");
        // let ipfs_hash:String = utf8(b"arjit singh");
        // let streaming_timestamp: u64=timestamp::now_seconds();
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

