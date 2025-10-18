// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title SimpleCouncil
 * @author Brevis Network
 * @notice A minimal, fixed-parameter council for external call proposals
 * @dev One address = one vote. Immutable requiredYesVotes and activePeriod (secs) are set at construction.
 *      Proposals are external calls (keccak256(target, data)). Proposer and executor auto-vote yes.
 *      Deadline is zeroed before external calls (reentrancy guard). Quorum: yesVotes >= requiredYesVotes.
 */
contract SimpleCouncil {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// Absolute number of "yes" votes required for a proposal to pass
    uint256 public immutable requiredYesVotes;
    /// Proposal active period in seconds (after which proposals expire)
    uint256 public immutable activePeriod;

    /// EnumerableSet of voter addresses, expected to be small in number
    EnumerableSet.AddressSet private voters;

    /// Proposal data structure containing hash, deadline, and votes
    struct Proposal {
        bytes32 dataHash; // keccak256(abi.encodePacked(_target, _data))
        uint256 deadline; // Timestamp when proposal expires
        mapping(address => bool) votes; // Voter address -> vote (true = yes, false = no)
    }

    /// Mapping of proposal IDs to their data
    mapping(uint256 => Proposal) public proposals;

    /// Counter for generating unique proposal IDs
    uint256 public nextProposalId;

    event ProposalCreated(uint256 proposalId, address target, bytes data, uint256 deadline, address proposer);
    event ProposalVoted(uint256 proposalId, address voter, bool vote);
    event ProposalExecuted(uint256 proposalId);

    error EmptyVoters();
    error OnlyVoterCanVote();
    error DeadlinePassed();
    error OnlyVoterCanCreateProposal();
    error OnlyVoterCanExecuteProposal();
    error DataHashMismatch();
    error NotEnoughVotes();
    error InvalidVoter();
    error InvalidRequiredYesVotes();

    /**
     * @notice Initializes the council with the provided voter addresses and quorum requirement
     * @param _voters Initial voter list (must be non-empty)
     * @param _requiredYesVotes Absolute number of yes votes required to pass a proposal
     * @param _activePeriod Proposal active period in seconds; if 0, defaults to 86400 (1 day)
     */
    constructor(address[] memory _voters, uint256 _requiredYesVotes, uint256 _activePeriod) {
        if (_voters.length == 0) revert EmptyVoters();
        for (uint256 i = 0; i < _voters.length; i++) {
            if (_voters[i] == address(0)) revert InvalidVoter();
            voters.add(_voters[i]);
        }
        if (_requiredYesVotes == 0 || _requiredYesVotes > voters.length()) revert InvalidRequiredYesVotes();
        requiredYesVotes = _requiredYesVotes;
        activePeriod = _activePeriod == 0 ? 86400 : _activePeriod;
    }

    /**
     * @notice Creates a new proposal for an external call and auto-votes yes for the proposer
     * @param _target The target contract address to call
     * @param _data The encoded function call data
     * @return proposalId The ID of the created proposal
     */
    function createProposal(address _target, bytes memory _data) public returns (uint256 proposalId) {
        if (!voters.contains(msg.sender)) revert OnlyVoterCanCreateProposal();
        proposalId = nextProposalId;
        nextProposalId += 1;
        Proposal storage p = proposals[proposalId];
        p.dataHash = keccak256(abi.encodePacked(_target, _data));
        p.deadline = block.timestamp + activePeriod;
        p.votes[msg.sender] = true;
        emit ProposalCreated(proposalId, _target, _data, p.deadline, msg.sender);
    }

    /**
     * @notice Casts or updates a vote on a proposal
     * @param _proposalId The ID of the proposal to vote on
     * @param _vote The vote (true = yes, false = no)
     */
    function voteProposal(uint256 _proposalId, bool _vote) public {
        if (!voters.contains(msg.sender)) revert OnlyVoterCanVote();
        Proposal storage p = proposals[_proposalId];
        if (block.timestamp >= p.deadline) revert DeadlinePassed();
        p.votes[msg.sender] = _vote;
        emit ProposalVoted(_proposalId, msg.sender, _vote);
    }

    /**
     * @notice Executes a proposal if it has sufficient votes and is still active
     * @dev Reentrancy is prevented by zeroing the deadline before external call
     * @param _proposalId The ID of the proposal to execute
     * @param _target The target contract address (must match the original)
     * @param _data The encoded function call data (must match the original)
     */
    function executeProposal(uint256 _proposalId, address _target, bytes calldata _data) public {
        if (!voters.contains(msg.sender)) revert OnlyVoterCanExecuteProposal();
        Proposal storage p = proposals[_proposalId];
        if (block.timestamp >= p.deadline) revert DeadlinePassed();
        if (p.dataHash != keccak256(abi.encodePacked(_target, _data))) revert DataHashMismatch();

        // Prevent reentrancy by setting deadline to 0 before external calls
        p.deadline = 0;

        // Executor automatically votes yes
        p.votes[msg.sender] = true;
        (, bool hasQuorum) = countVotes(_proposalId);
        if (!hasQuorum) revert NotEnoughVotes();

        // Execute the proposed call
        (bool success, bytes memory res) = _target.call(_data);
        if (!success) {
            assembly {
                // revert with the exact returndata from the failed call
                revert(add(res, 0x20), mload(res))
            }
        }
        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Counts the votes for a proposal and determines if quorum is met
     * @param _proposalId The ID of the proposal to count votes for
     * @return yesVotes The total number of "yes" votes
     * @return hasQuorum Whether the proposal has enough votes to pass (yesVotes >= requiredYesVotes)
     */
    function countVotes(uint256 _proposalId) public view returns (uint256 yesVotes, bool hasQuorum) {
        uint256 totalVoters = voters.length();
        for (uint256 i = 0; i < totalVoters; i++) {
            address voter = voters.at(i);
            if (getVote(_proposalId, voter)) yesVotes += 1;
        }
        hasQuorum = yesVotes >= requiredYesVotes;
    }

    /**
     * @notice Returns how a specific voter voted on a proposal
     * @param _proposalId The ID of the proposal to check
     * @param _voter The address of the voter to check
     * @return vote The vote cast by the voter (true = yes, false = no or no vote)
     */
    function getVote(uint256 _proposalId, address _voter) public view returns (bool vote) {
        return proposals[_proposalId].votes[_voter];
    }

    /**
     * @notice Checks whether an address is a registered voter
     * @param _addr The address to check for voter membership
     * @return True if the address is a voter, false otherwise
     */
    function isVoter(address _addr) external view returns (bool) {
        return voters.contains(_addr);
    }

    /**
     * @notice Returns the full list of voter addresses
     */
    function getVoters() external view returns (address[] memory voterList) {
        uint256 totalVoters = voters.length();
        voterList = new address[](totalVoters);
        for (uint256 i = 0; i < totalVoters; i++) {
            voterList[i] = voters.at(i);
        }
        return voterList;
    }

    /**
     * @notice Returns the voters who currently have the requested vote value for a proposal
     * @param _proposalId The proposal to inspect
     * @param _vote Set to true to return yes voters; set to false to return voters with false in the votes map
     */
    function getVotersByVote(uint256 _proposalId, bool _vote) external view returns (address[] memory voterList) {
        (uint256 yesCount,) = countVotes(_proposalId);
        uint256 total = voters.length();
        uint256 cap = _vote ? yesCount : total - yesCount;
        voterList = new address[](cap);

        uint256 idx;
        for (uint256 i = 0; i < total; i++) {
            address voter = voters.at(i);
            if (proposals[_proposalId].votes[voter] == _vote) {
                voterList[idx++] = voter;
                if (idx == cap) break;
            }
        }
    }
}
