address radio_addrx{
   



module OnChainRadioGovernance {
use aptos_framework::aptos_governance;
use std::signer; 
use std::account; 
use std::vector;
use std::debug::print;
use aptos_framework::stake;
use radio_addrx::voting;
    /// Configurations of the AptosGovernance, set during Genesis and can be updated by the same process offered
    /// by this AptosGovernance module.
    struct GovernanceConfig has key {
        min_voting_threshold: u128,
        required_proposer_stake: u64,
        voting_duration_secs: u64,
    }

    public entry fun Initialize_stake_owner(
        owner: &signer,
        initial_stake_amount: u64,
        operator: address,
        voter: address,
    ){
        stake::initialize_stake_owner(owner,initial_stake_amount,operator,voter);
    }

    /// Add `amount` of coins from the `account` owning the StakePool.
    public entry fun Add_stake(owner: &signer, amount: u64){
        stake::add_stake(owner, amount);
    }


    // fun Create_proposal_metadata(metadata_location: vector<u8>, metadata_hash: vector<u8>): SimpleMap<String, vector<u8>> {
    //     aptos_governance::create_proposal_metadata(metadata_location, metadata_hash)
    // }


    // create a single step proposal
    public entry fun Create_Single_Step_Proposal(proposer: &signer, stake_pool: address, execution_hash: vector<u8>, metadata_location: vector<u8>, metadata_hash: vector<u8>){
        aptos_governance::create_proposal_v2(proposer, stake_pool, execution_hash, metadata_location, metadata_hash, false);
    }

    // create multi step proposal
    public entry fun Create_Multi_Step_Proposal(proposer: &signer, stake_pool: address, execution_hash: vector<u8>, metadata_location: vector<u8>, metadata_hash: vector<u8>){
        aptos_governance::create_proposal_v2(proposer, stake_pool, execution_hash, metadata_location, metadata_hash,true);
    }

    /// Vote on proposal with `proposal_id` and all voting power from `stake_pool`.
    public entry fun Vote(voter: &signer, stake_pool: address, proposal_id: u64, should_pass: bool){
        aptos_governance::vote(voter, stake_pool, proposal_id, should_pass);
    }

    /// Vote on proposal with `proposal_id` and specified voting power from `stake_pool`.
    public entry fun Partial_vote(
        voter: &signer,
        stake_pool: address,
        proposal_id: u64,
        voting_power: u64,
        should_pass: bool
    ){
        aptos_governance::partial_vote(voter,stake_pool,proposal_id,voting_power,should_pass);
    }

    // add_approved_script_hash

    /// Resolve a successful single-step proposal. This would fail if the proposal is not successful (not enough votes or more no than yes).
    public fun Resolve(proposal_id: u64, signer_address: address):signer{
        aptos_governance::resolve(proposal_id, signer_address)
    }

    /// Resolve a successful multi-step proposal. This would fail if the proposal is not successful.
    public fun Resolve_multi_step_proposal(proposal_id: u64, signer_address: address, next_execution_hash: vector<u8>): signer{
        aptos_governance::resolve_multi_step_proposal(proposal_id, signer_address, next_execution_hash)
    }

    /// Remove an approved proposal's execution script hash.
    public fun Remove_approved_hash(proposal_id: u64){
        aptos_governance::remove_approved_hash(proposal_id);
    }

    #[view]
    /// Return the voting power a stake pool has with respect to governance proposals.
    public fun Get_voting_power(pool_address: address): u64 {
        aptos_governance::get_voting_power(pool_address)
    }
    #[view]
    public fun Get_voting_duration_secs(): u64{
        aptos_governance::get_voting_duration_secs()
    }

    #[view]
    public fun Get_min_voting_threshold(): u128{
        aptos_governance::get_min_voting_threshold()
    }

    #[view]
    public fun Get_required_proposer_stake(): u64{
        aptos_governance::get_required_proposer_stake()
    }

    #[view]
    /// Return true if a stake pool has already voted on a proposal before partial governance voting is enabled.
        public fun Has_entirely_voted(stake_pool: address, proposal_id: u64): bool{
        aptos_governance::has_entirely_voted(stake_pool, proposal_id)
    }

    #[view]
    /// Return remaining voting power of a stake pool on a proposal.
    /// Note: a stake pool's voting power on a proposal could increase over time(e.g. rewards/new stake).
    public fun Get_remaining_voting_power(stake_pool: address, proposal_id: u64): u64 {
        aptos_governance::get_remaining_voting_power(stake_pool, proposal_id)
    }



    #[test (proposer=@0x123,voter=@0x234)]
    public entry fun test_create_proposal(proposer:&signer,voter:&signer) {
        account::create_account_for_test(signer::address_of(proposer));
        account::create_account_for_test(signer::address_of(voter));
        let multi_step:bool =false;
        let execution_hash = vector::empty<u8>();
        vector::push_back(&mut execution_hash, 1);
        print(&multi_step);
        print(&execution_hash);
        Initialize_stake_owner(proposer,0,signer::address_of(proposer),signer::address_of(voter));
        // print(account::balance<AptosCoin>(proposer))
        // if (multi_step) {
        //     Create_Multi_Step_Proposal(
        //         proposer,
        //         signer::address_of(proposer),
        //         execution_hash,
        //         b"",
        //         b""
        //     );
        // } else {
        //     Create_Single_Step_Proposal(
        //         proposer,
        //         signer::address_of(proposer),
        //         execution_hash,
        //         b"",
        //         b""
        //     );
        // };

    }

    // #[test]



}
}