///
/// This is the general Voting module that can be used as part of a DAO Governance. Voting is designed to be used by
/// standalone governance modules, who has full control over the voting flow and is responsible for voting power
/// calculation and including proper capabilities when creating the proposal so resolution can go through.
/// On-chain governance of the Aptos network also uses Voting.
///
/// The voting flow:
/// 1. The Voting module can be deployed at a known address (e.g. 0x1 for Aptos on-chain governance)
/// 2. The governance module, e.g. AptosGovernance, can be deployed later and define a GovernanceProposal resource type
/// that can also contain other information such as Capability resource for authorization.
/// 3. The governance module's owner can then register the ProposalType with Voting. This also hosts the proposal list
/// (forum) on the calling account.
/// 4. A proposer, through the governance module, can call Voting::create_proposal to create a proposal. create_proposal
/// cannot be called directly not through the governance module. A script hash of the resolution script that can later
/// be called to execute the proposal is required.
/// 5. A voter, through the governance module, can call Voting::vote on a proposal. vote requires passing a &ProposalType
/// and thus only the governance module that registers ProposalType can call vote.
/// 6. Once the proposal's expiration time has passed and more than the defined threshold has voted yes on the proposal,
/// anyone can call resolve which returns the content of the proposal (of type ProposalType) that can be used to execute.
/// 7. Only the resolution script with the same script hash specified in the proposal can call Voting::resolve as part of
/// the resolution process.
module radio_addrx::voting {
    use std::bcs::to_bytes;
    use std::error;
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{String, utf8};
    use std::vector;

    use aptos_std::from_bcs::to_u64;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::{Self, TypeInfo};

    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_framework::transaction_context;
    use aptos_std::from_bcs;

    /// Proposal cannot be resolved more than once
    const EPROPOSAL_ALREADY_RESOLVED: u64 = 3;
    /// Proposal cannot contain an empty execution script hash
    const EPROPOSAL_EMPTY_EXECUTION_HASH: u64 = 4;
    /// Proposal's voting period has already ended.
    const EPROPOSAL_VOTING_ALREADY_ENDED: u64 = 5;
    /// Voting forum has already been registered.
    const EVOTING_FORUM_ALREADY_REGISTERED: u64 = 6;
    /// Minimum vote threshold cannot be higher than early resolution threshold.
    const EINVALID_MIN_VOTE_THRESHOLD: u64 = 7;

    /// ProposalStateEnum representing proposal state.
    const PROPOSAL_STATE_PENDING: u64 = 0;
    const PROPOSAL_STATE_SUCCEEDED: u64 = 1;
    /// Proposal has failed because either the min vote threshold is not met or majority voted no.
    const PROPOSAL_STATE_FAILED: u64 = 3;

    /// Key used to track the resolvable time in the proposal's metadata.
    const RESOLVABLE_TIME_METADATA_KEY: vector<u8> = b"RESOLVABLE_TIME_METADATA_KEY";
   

    /// Extra metadata (e.g. description, code url) can be part of the ProposalType struct.
    struct Proposal<ProposalType: store> has store,drop {
        /// Required. The address of the proposer.
        proposer: address,
        /// Timestamp when the proposal was created.
        creation_time_secs: u64,
        /// Required. The hash for the execution script module. Only the same exact script module can resolve this proposal.
        execution_hash: vector<u8>,
        /// A proposal is only resolved if expiration has passed and the number of votes is above threshold.
        min_vote_threshold: u128,
        expiration_secs: u64,

        /// Number of votes for each outcome.
        /// u128 since the voting power is already u64 and can add up to more than u64 can hold.
        yes_votes: u128,
        no_votes: u128,

        /// Whether the proposal has been resolved.
        is_resolved: bool,
        /// Resolution timestamp if the proposal has been resolved. 0 otherwise.
        resolution_time_secs: u64,
    }

    struct VotingForum<ProposalType: store> has key {
        /// Use Table for execution optimization instead of Vector for gas cost since Vector is read entirely into memory
        /// during execution while only relevant Table entries are.
        proposals: Table<u64, Proposal<ProposalType>>,
        events: VotingEvents,
        /// Unique identifier for a proposal. This allows for 2 * 10**19 proposals.
        next_proposal_id: u64,
    }

    struct VotingEvents has store{
        create_proposal_events: EventHandle<CreateProposalEvent>,
        register_forum_events: EventHandle<RegisterForumEvent>,
        resolve_proposal_events: EventHandle<ResolveProposal>,
        vote_events: EventHandle<VoteEvent>,
    }

    struct CreateProposalEvent has drop, store {
        proposal_id: u64,
        early_resolution_vote_threshold: Option<u128>,
        execution_hash: vector<u8>,
        expiration_secs: u64,
        min_vote_threshold: u128,
    }

    struct RegisterForumEvent has drop, store {
        hosting_account: address,
        proposal_type_info: TypeInfo,
    }

    struct VoteEvent has drop, store {
        proposal_id: u64,
        num_votes: u64,
    }

    struct ResolveProposal has drop, store {
        proposal_id: u64,
        yes_votes: u128,
        no_votes: u128,
        // resolved_early: bool
    }

    public fun register<ProposalType: store>(account: &signer) {
        let addr = signer::address_of(account);
        assert!(!exists<VotingForum<ProposalType>>(addr), error::already_exists(EVOTING_FORUM_ALREADY_REGISTERED));

        let voting_forum = VotingForum<ProposalType> {
            next_proposal_id: 0,
            proposals: table::new<u64, Proposal<ProposalType>>(),
            events: VotingEvents {
                create_proposal_events: account::new_event_handle<CreateProposalEvent>(account),
                register_forum_events: account::new_event_handle<RegisterForumEvent>(account),
                resolve_proposal_events: account::new_event_handle<ResolveProposal>(account),
                vote_events: account::new_event_handle<VoteEvent>(account),
            }
        };

        event::emit_event<RegisterForumEvent>(
            &mut voting_forum.events.register_forum_events,
            RegisterForumEvent {
                hosting_account: addr,
                proposal_type_info: type_info::type_of<ProposalType>(),
            },
        );

        move_to(account, voting_forum);
    }

    /// Create a single-step with the given parameters
    ///
    /// @param voting_forum_address The forum's address where the proposal will be stored.
    /// @param execution_content The execution content that will be given back at resolution time. This can contain
    /// data such as a capability resource used to scope the execution.
    /// @param execution_hash The sha-256 hash for the execution script module. Only the same exact script module can
    /// resolve this proposal.
    /// @param min_vote_threshold The minimum number of votes needed to consider this proposal successful.
    /// @param expiration_secs The time in seconds at which the proposal expires and can potentially be resolved.
    /// @param early_resolution_vote_threshold The vote threshold for early resolution of this proposal.
    /// @param metadata A simple_map that stores information about this proposal.
    /// @param is_multi_step_proposal A bool value that indicates if the proposal is single-step or multi-step.
    /// @return The proposal id.
    public fun create_proposal_v2<ProposalType: drop+store>(
        proposer: address,
        voting_forum_address: address,
        execution_content: ProposalType,
        execution_hash: vector<u8>,
        min_vote_threshold: u128,
        expiration_secs: u64,
        early_resolution_vote_threshold: Option<u128>,
    ): u64 acquires VotingForum {
        if (option::is_some(&early_resolution_vote_threshold)) {
            assert!(
                min_vote_threshold <= *option::borrow(&early_resolution_vote_threshold),
                error::invalid_argument(EINVALID_MIN_VOTE_THRESHOLD),
            );
        };
        // Make sure the execution script's hash is not empty.
        assert!(vector::length(&execution_hash) > 0, error::invalid_argument(EPROPOSAL_EMPTY_EXECUTION_HASH));

        let voting_forum = borrow_global_mut<VotingForum<ProposalType>>(voting_forum_address);
        let proposal_id = voting_forum.next_proposal_id;
        voting_forum.next_proposal_id = voting_forum.next_proposal_id + 1;

        table::add(&mut voting_forum.proposals, proposal_id, Proposal {
            proposer,
            creation_time_secs: timestamp::now_seconds(),
            execution_hash,
            min_vote_threshold,
            expiration_secs,
            yes_votes: 0,
            no_votes: 0,
            is_resolved: false,
            resolution_time_secs: 0,
        });

        event::emit_event<CreateProposalEvent>(
            &mut voting_forum.events.create_proposal_events,
            CreateProposalEvent {
                proposal_id,
                early_resolution_vote_threshold,
                execution_hash,
                expiration_secs,
                min_vote_threshold,
            },
        );
        proposal_id
    }

    /// Vote on the given proposal.
    ///
    /// @param _proof Required so only the governance module that defines ProposalType can initiate voting.
    ///               This guarantees that voting eligibility and voting power are controlled by the right governance.
    /// @param voting_forum_address The address of the forum where the proposals are stored.
    /// @param proposal_id The proposal id.
    /// @param num_votes Number of votes. Voting power should be calculated by governance.
    /// @param should_pass Whether the votes are for yes or no.
    public fun vote<ProposalType: store>(
        _proof: &ProposalType,
        voting_forum_address: address,
        proposal_id: u64,
        num_votes: u64,
        should_pass: bool,
    ) acquires VotingForum {
        let voting_forum = borrow_global_mut<VotingForum<ProposalType>>(voting_forum_address);
        let proposal = table::borrow_mut(&mut voting_forum.proposals, proposal_id);
        // Voting might still be possible after the proposal has enough yes votes to be resolved early. This would only
        // lead to possible proposal resolution failure if the resolve early threshold is not definitive (e.g. < 50% + 1
        // of the total voting token's supply). In this case, more voting might actually still be desirable.
        // Governance mechanisms built on this voting module can apply additional rules on when voting is closed as
        // appropriate.
        assert!(!is_voting_period_over(proposal), error::invalid_state(EPROPOSAL_VOTING_ALREADY_ENDED));
        assert!(!proposal.is_resolved, error::invalid_state(EPROPOSAL_ALREADY_RESOLVED));

        if (should_pass) {
            proposal.yes_votes = proposal.yes_votes + (num_votes as u128);
        } else {
            proposal.no_votes = proposal.no_votes + (num_votes as u128);
        };

        // Record the resolvable time to ensure that resolution has to be done non-atomically.
        // let timestamp_secs_bytes = to_bytes(&timestamp::now_seconds());
        // let key = utf8(RESOLVABLE_TIME_METADATA_KEY);

        event::emit_event<VoteEvent>(
            &mut voting_forum.events.vote_events,
            VoteEvent { proposal_id, num_votes },
        );
    }


    /// Resolve a single-step proposal with the given id.
    /// Can only be done if there are at least as many votes as min required and
    /// there are more yes votes than no. If either of these conditions is not met, this will revert.
    ///
    ///
    /// @param voting_forum_address The address of the forum where the proposals are stored.
    /// @param proposal_id The proposal id.
    /// @param next_execution_hash The next execution hash if the given proposal is multi-step.
    public fun resolve_proposal_v2<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ) acquires VotingForum {
        let voting_forum = borrow_global_mut<VotingForum<ProposalType>>(voting_forum_address);
        let proposal = table::borrow_mut(&mut voting_forum.proposals, proposal_id);
        event::emit_event<ResolveProposal>(
            &mut voting_forum.events.resolve_proposal_events,
            ResolveProposal {
                proposal_id,
                yes_votes: proposal.yes_votes,
                no_votes: proposal.no_votes,
            },
        );
    }
    #[view]
    /// Return the next unassigned proposal id
    public fun next_proposal_id<ProposalType: store>(voting_forum_address: address,): u64 acquires VotingForum {
        let voting_forum = borrow_global<VotingForum<ProposalType>>(voting_forum_address);
        voting_forum.next_proposal_id
    }

    #[view]
    public fun get_proposer<ProposalType: store>(voting_forum_address: address, proposal_id: u64): address acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        proposal.proposer
    }

    #[view]
    public fun is_voting_closed<ProposalType: store>(voting_forum_address: address, proposal_id: u64): bool acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        is_voting_period_over(proposal)
    }


    #[view]
    /// Return the state of the proposal with given id.
    ///
    /// @param voting_forum_address The address of the forum where the proposals are stored.
    /// @param proposal_id The proposal id.
    /// @return Proposal state as an enum value.
    public fun get_proposal_state<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): u64 acquires VotingForum {
        if (is_voting_closed<ProposalType>(voting_forum_address, proposal_id)) {
            let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
            let yes_votes = proposal.yes_votes;
            let no_votes = proposal.no_votes;

            if (yes_votes > no_votes && yes_votes + no_votes >= proposal.min_vote_threshold) {
                PROPOSAL_STATE_SUCCEEDED
            } else {
                PROPOSAL_STATE_FAILED
            }
        } else {
            PROPOSAL_STATE_PENDING
        }
    }

    #[view]
    /// Return the proposal's creation time.
    public fun get_proposal_creation_secs<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): u64 acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        proposal.creation_time_secs
    }

    #[view]
    /// Return the proposal's expiration time.
    public fun get_proposal_expiration_secs<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): u64 acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        proposal.expiration_secs
    }

    #[view]
    /// Return the proposal's execution hash.
    public fun get_execution_hash<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): vector<u8> acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        proposal.execution_hash
    }

    #[view]
    /// Return the proposal's minimum vote threshold
    public fun get_min_vote_threshold<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): u128 acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        proposal.min_vote_threshold
    }

    #[view]
    /// Return the proposal's current vote count (yes_votes, no_votes)
    public fun get_votes<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): (u128, u128) acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        (proposal.yes_votes, proposal.no_votes)
    }

    #[view]
    /// Return true if the governance proposal has already been resolved.
    public fun is_resolved<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): bool acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        proposal.is_resolved
    }

    #[view]
    public fun get_resolution_time_secs<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): u64 acquires VotingForum {
        let proposal = get_proposal<ProposalType>(voting_forum_address, proposal_id);
        proposal.resolution_time_secs
    }

    /// Return true if the voting period of the given proposal has already ended.
    fun is_voting_period_over<ProposalType: store>(proposal: &Proposal<ProposalType>): bool {
        timestamp::now_seconds() > proposal.expiration_secs
    }

    inline fun get_proposal<ProposalType: store>(
        voting_forum_address: address,
        proposal_id: u64,
    ): &Proposal<ProposalType> acquires VotingForum {
        let voting_forum = borrow_global<VotingForum<ProposalType>>(voting_forum_address);
        table::borrow(&voting_forum.proposals, proposal_id)
    }

    #[test_only]
    struct RadioProposal has store,drop {}

    #[test_only]
    const VOTING_DURATION_SECS: u64 = 100000;

    #[test_only]
    public fun create_test_proposal_generic(
        governance: &signer,
        early_resolution_threshold: Option<u128>,
        // use_generic_create_proposal_function: bool,
    ): u64 acquires VotingForum {
        // Register voting forum and create a proposal.
        register<RadioProposal>(governance);
        let governance_address = signer::address_of(governance);
        let proposal = RadioProposal {};

        // This works because our Move unit test extensions mock out the execution hash to be [1].
        let execution_hash = vector::empty<u8>();
        vector::push_back(&mut execution_hash, 1);
        // let metadata = simple_map::create<String, vector<u8>>();

        create_proposal_v2<RadioProposal>(
                governance_address,
                governance_address,
                proposal,
                execution_hash,
                10,
                timestamp::now_seconds() + VOTING_DURATION_SECS,
                early_resolution_threshold,
            )
    }

    // #[test_only]
    // public fun resolve_proposal_for_test<ProposalType>(voting_forum_address: address, proposal_id: u64, is_multi_step: bool, finish_multi_step_execution: bool) acquires VotingForum {
    //     if (is_multi_step) {
    //         let execution_hash = vector::empty<u8>();
    //         vector::push_back(&mut execution_hash, 1);
    //         resolve_proposal_v2<RadioProposal>(voting_forum_address, proposal_id);

    //         if (finish_multi_step_execution) {
    //             resolve_proposal_v2<RadioProposal>(voting_forum_address, proposal_id);
    //         };
    //     } else {
    //         let proposal = resolve<RadioProposal>(voting_forum_address, proposal_id);
    //         let RadioProposal {} = proposal;
    //     };
    // }

    #[test_only]
    public fun create_test_proposal(
        governance: &signer,
        early_resolution_threshold: Option<u128>,
    ): u64 acquires VotingForum {
        create_test_proposal_generic(governance, early_resolution_threshold)
    }

    #[test_only]
    public fun create_proposal_with_empty_execution_hash_should_fail_generic(governance: &signer) acquires VotingForum {
        account::create_account_for_test(@aptos_framework);
        let governance_address = signer::address_of(governance);
        account::create_account_for_test(governance_address);
        register<RadioProposal>(governance);
        let proposal = RadioProposal {};

        create_proposal_v2<RadioProposal>(
                governance_address,
                governance_address,
                proposal,
                b"",
                10,
                100000,
                option::none<u128>(),
            );
    }

    #[test(governance = @0x123)]
    #[expected_failure(abort_code = 0x10004, location = Self)]
    public fun create_proposal_with_empty_execution_hash_should_fail(governance: &signer) acquires VotingForum {
        create_proposal_with_empty_execution_hash_should_fail_generic(governance);
    }


    // #[test_only]
    // public entry fun test_voting_passed_generic(aptos_framework: &signer, governance: &signer, use_create_multi_step: bool, use_resolve_multi_step: bool) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);

    //     // Register voting forum and create a proposal.
    //     let governance_address = signer::address_of(governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(governance, option::none<u128>(), use_create_multi_step);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_PENDING, 0);

    //     // Vote.
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 10, true);
    //     let RadioProposal {} = proof;

    //     // Resolve.
    //     timestamp::fast_forward_seconds(VOTING_DURATION_SECS + 1);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_SUCCEEDED, 1);

    //     // This if statement is specifically for the test `test_voting_passed_single_step_can_use_generic_function()`.
    //     // It's testing when we have a single-step proposal that was created by the single-step `create_proposal()`,
    //     // we should be able to successfully resolve it using the generic `resolve_proposal_v2` function.
    //     if (!use_create_multi_step && use_resolve_multi_step) {
    //         resolve_proposal_v2<RadioProposal>(governance_address, proposal_id, vector::empty<u8>());
    //     } else {
    //         resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, use_resolve_multi_step, true);
    //     };
    //     let voting_forum = borrow_global<VotingForum<RadioProposal>>(governance_address);
    //     assert!(table::borrow(&voting_forum.proposals, proposal_id).is_resolved, 2);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // public entry fun test_voting_passed(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_passed_generic(aptos_framework, governance, false, false);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // public entry fun test_voting_passed_multi_step(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_passed_generic(aptos_framework, governance, true, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code=0x5000a, location = Self)]
    // public entry fun test_voting_passed_multi_step_cannot_use_single_step_resolve_function(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_passed_generic(aptos_framework, governance, true, false);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // public entry fun test_voting_passed_single_step_can_use_generic_function(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_passed_generic(aptos_framework, governance, false, true);
    // }

    // #[test_only]
    // public entry fun test_cannot_resolve_twice_generic(aptos_framework: &signer, governance: &signer, is_multi_step: bool) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);

    //     // Register voting forum and create a proposal.
    //     let governance_address = signer::address_of(governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(governance, option::none<u128>(), is_multi_step);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_PENDING, 0);

    //     // Vote.
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 10, true);
    //     let RadioProposal {} = proof;

    //     // Resolve.
    //     timestamp::fast_forward_seconds(VOTING_DURATION_SECS + 1);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_SUCCEEDED, 1);
    //     resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, is_multi_step, true);
    //     resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, is_multi_step, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30003, location = Self)]
    // public entry fun test_cannot_resolve_twice(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_cannot_resolve_twice_generic(aptos_framework, governance, false);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30003, location = Self)]
    // public entry fun test_cannot_resolve_twice_multi_step(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_cannot_resolve_twice_generic(aptos_framework, governance, true);
    // }

    // #[test_only]
    // public entry fun test_voting_passed_early_generic(aptos_framework: &signer, governance: &signer, is_multi_step: bool) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);

    //     // Register voting forum and create a proposal.
    //     let governance_address = signer::address_of(governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(governance, option::some(100), is_multi_step);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_PENDING, 0);

    //     // Assert that IS_MULTI_STEP_PROPOSAL_IN_EXECUTION_KEY has value `false` in proposal.metadata.
    //     if (is_multi_step) {
    //         assert!(!is_multi_step_proposal_in_execution<RadioProposal>(governance_address, 0), 1);
    //     };

    //     // Vote.
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 100, true);
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 10, false);
    //     let RadioProposal {} = proof;

    //     // Resolve early. Need to increase timestamp as resolution cannot happen in the same tx.
    //     timestamp::fast_forward_seconds(1);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_SUCCEEDED, 2);

    //     if (is_multi_step) {
    //         // Assert that IS_MULTI_STEP_PROPOSAL_IN_EXECUTION_KEY still has value `false` in proposal.metadata before execution.
    //         assert!(!is_multi_step_proposal_in_execution<RadioProposal>(governance_address, 0), 3);
    //         resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, is_multi_step, false);

    //         // Assert that the multi-step proposal is in execution but not resolved yet.
    //         assert!(is_multi_step_proposal_in_execution<RadioProposal>(governance_address, 0), 4);
    //         let voting_forum = borrow_global_mut<VotingForum<RadioProposal>>(governance_address);
    //         let proposal = table::borrow_mut(&mut voting_forum.proposals, proposal_id);
    //         assert!(!proposal.is_resolved, 5);
    //     };

    //     resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, is_multi_step, true);
    //     let voting_forum = borrow_global_mut<VotingForum<RadioProposal>>(governance_address);
    //     assert!(table::borrow(&voting_forum.proposals, proposal_id).is_resolved, 6);

    //     // Assert that the IS_MULTI_STEP_PROPOSAL_IN_EXECUTION_KEY value is set back to `false` upon successful resolution of this multi-step proposal.
    //     if (is_multi_step) {
    //         assert!(!is_multi_step_proposal_in_execution<RadioProposal>(governance_address, 0), 7);
    //     };
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // public entry fun test_voting_passed_early(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_passed_early_generic(aptos_framework, governance, false);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // public entry fun test_voting_passed_early_multi_step(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_passed_early_generic(aptos_framework, governance, true);
    // }

    // #[test_only]
    // public entry fun test_voting_passed_early_in_same_tx_should_fail_generic(
    //     aptos_framework: &signer,
    //     governance: &signer,
    //     is_multi_step: bool
    // ) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);
    //     let governance_address = signer::address_of(governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(governance, option::some(100), is_multi_step);
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 40, true);
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 60, true);
    //     let RadioProposal {} = proof;

    //     // Resolving early should fail since timestamp hasn't changed since the last vote.
    //     resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, is_multi_step, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30008, location = Self)]
    // public entry fun test_voting_passed_early_in_same_tx_should_fail(
    //     aptos_framework: &signer,
    //     governance: &signer
    // ) acquires VotingForum {
    //     test_voting_passed_early_in_same_tx_should_fail_generic(aptos_framework, governance, false);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30008, location = Self)]
    // public entry fun test_voting_passed_early_in_same_tx_should_fail_multi_step(
    //     aptos_framework: &signer,
    //     governance: &signer
    // ) acquires VotingForum {
    //     test_voting_passed_early_in_same_tx_should_fail_generic(aptos_framework, governance, true);
    // }

    // #[test_only]
    // public entry fun test_voting_failed_generic(aptos_framework: &signer, governance: &signer, is_multi_step: bool) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);

    //     // Register voting forum and create a proposal.
    //     let governance_address = signer::address_of(governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(governance, option::none<u128>(), is_multi_step);

    //     // Vote.
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 10, true);
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 100, false);
    //     let RadioProposal {} = proof;

    //     // Resolve.
    //     timestamp::fast_forward_seconds(VOTING_DURATION_SECS + 1);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_FAILED, 1);
    //     resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, is_multi_step, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30002, location = Self)]
    // public entry fun test_voting_failed(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_failed_generic(aptos_framework, governance, false);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30002, location = Self)]
    // public entry fun test_voting_failed_multi_step(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_failed_generic(aptos_framework, governance, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30005, location = Self)]
    // public entry fun test_cannot_vote_after_voting_period_is_over(
    //     aptos_framework: signer,
    //     governance: signer
    // ) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(&aptos_framework);
    //     let governance_address = signer::address_of(&governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal(&governance, option::none<u128>());
    //     // Voting period is over. Voting should now fail.
    //     timestamp::fast_forward_seconds(VOTING_DURATION_SECS + 1);
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 10, true);
    //     let RadioProposal {} = proof;
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code=0x30009, location = Self)]
    // public entry fun test_cannot_vote_after_multi_step_proposal_starts_executing(
    //     aptos_framework: signer,
    //     governance: signer
    // ) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(&aptos_framework);

    //     // Register voting forum and create a proposal.
    //     let governance_address = signer::address_of(&governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(&governance, option::some(100), true);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_PENDING, 0);

    //     // Vote.
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 100, true);

    //     // Resolve early.
    //     timestamp::fast_forward_seconds(1);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_SUCCEEDED, 1);
    //     resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, true, false);
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 100, false);
    //     let RadioProposal {} = proof;
    // }

    // #[test_only]
    // public entry fun test_voting_failed_early_generic(aptos_framework: &signer, governance: &signer, is_multi_step: bool) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);

    //     // Register voting forum and create a proposal.
    //     let governance_address = signer::address_of(governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(governance, option::some(100), is_multi_step);

    //     // Vote.
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 100, true);
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 100, false);
    //     let RadioProposal {} = proof;

    //     // Resolve.
    //     timestamp::fast_forward_seconds(VOTING_DURATION_SECS + 1);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_FAILED, 1);
    //     resolve_proposal_for_test<RadioProposal>(governance_address, proposal_id, is_multi_step, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30002, location = Self)]
    // public entry fun test_voting_failed_early(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_failed_early_generic(aptos_framework, governance, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x30002, location = Self)]
    // public entry fun test_voting_failed_early_multi_step(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     test_voting_failed_early_generic(aptos_framework, governance, false);
    // }

    // #[test_only]
    // public entry fun test_cannot_set_min_threshold_higher_than_early_resolution_generic(
    //     aptos_framework: &signer,
    //     governance: &signer,
    //     is_multi_step: bool,
    // ) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);
    //     account::create_account_for_test(signer::address_of(governance));
    //     // This should fail.
    //     create_test_proposal_generic(governance, option::some(5), is_multi_step);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x10007, location = Self)]
    // public entry fun test_cannot_set_min_threshold_higher_than_early_resolution(
    //     aptos_framework: &signer,
    //     governance: &signer,
    // ) acquires VotingForum {
    //     test_cannot_set_min_threshold_higher_than_early_resolution_generic(aptos_framework, governance, false);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // #[expected_failure(abort_code = 0x10007, location = Self)]
    // public entry fun test_cannot_set_min_threshold_higher_than_early_resolution_multi_step(
    //     aptos_framework: &signer,
    //     governance: &signer,
    // ) acquires VotingForum {
    //     test_cannot_set_min_threshold_higher_than_early_resolution_generic(aptos_framework, governance, true);
    // }

    // #[test(aptos_framework = @aptos_framework, governance = @0x123)]
    // public entry fun test_replace_execution_hash(aptos_framework: &signer, governance: &signer) acquires VotingForum {
    //     account::create_account_for_test(@aptos_framework);
    //     timestamp::set_time_has_started_for_testing(aptos_framework);

    //     // Register voting forum and create a proposal.
    //     let governance_address = signer::address_of(governance);
    //     account::create_account_for_test(governance_address);
    //     let proposal_id = create_test_proposal_generic(governance, option::none<u128>(), true);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_PENDING, 0);

    //     // Vote.
    //     let proof = RadioProposal {};
    //     vote<RadioProposal>(&proof, governance_address, proposal_id, 10, true);
    //     let RadioProposal {} = proof;

    //     // Resolve.
    //     timestamp::fast_forward_seconds(VOTING_DURATION_SECS + 1);
    //     assert!(get_proposal_state<RadioProposal>(governance_address, proposal_id) == PROPOSAL_STATE_SUCCEEDED, 1);

    //     resolve_proposal_v2<RadioProposal>(governance_address, proposal_id, vector[10u8]);
    //     let voting_forum = borrow_global<VotingForum<RadioProposal>>(governance_address);
    //     let proposal = table::borrow(&voting_forum.proposals, 0);
    //     assert!(proposal.execution_hash == vector[10u8], 2);
    //     assert!(!table::borrow(&voting_forum.proposals, proposal_id).is_resolved, 3);
    // }
}
