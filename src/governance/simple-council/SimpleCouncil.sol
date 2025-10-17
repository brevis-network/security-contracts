// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title SimpleCouncil
 * @author Brevis Network
 * @notice A minimal, fixed-parameter council for external call proposals
 * @dev 1 address = 1 vote; fixed thresholds (QuorumThreshold = 60) and active period (ActivePeriod = 1 day).
 *      Proposals are external calls identified by keccak256(target, data). Proposer auto-votes yes; executor
 *      auto-votes yes on execution. Deadline is zeroed before the external call to mitigate reentrancy; quorum is
 *      checked with a non-truncating comparison: yesVotes * 100 >= QuorumThreshold * totalVoters.
 */
contract SimpleCouncil {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// Quorum threshold percentage (out of 100) required for a proposal to pass
    uint256 public constant QuorumThreshold = 60;
    /// Proposal active period in seconds (after which proposals expire)
    uint256 public constant ActivePeriod = 86400;

    // EnumerableSet of voter addresses, expcted to be small in number
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

    event ProposalCreated(
        uint256 indexed proposalId, address indexed target, bytes data, uint256 deadline, address proposer
    );
    event ProposalVoted(uint256 indexed proposalId, address indexed voter, bool vote);
    event ProposalExecuted(uint256 indexed proposalId);

    error EmptyVoters();
    error InvalidCaller();
    error DeadlinePassed();
    error OnlyVoterCanCreateProposal();
    error OnlyVoterCanExecuteProposal();
    error DataHashMismatch();
    error NotEnoughVotes();
    error ExternalCallFailed(string reason);

    /**
     * @notice Initializes the council with the provided voter addresses
     * @param _voters Initial voter list (must be non-empty)
     */
    constructor(address[] memory _voters) {
        if (_voters.length == 0) revert EmptyVoters();
        for (uint256 i = 0; i < _voters.length; i++) {
            voters.add(_voters[i]);
        }
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
        p.deadline = block.timestamp + ActivePeriod;
        p.votes[msg.sender] = true;
        emit ProposalCreated(proposalId, _target, _data, p.deadline, msg.sender);
    }

    /**
     * @notice Casts or updates a vote on a proposal
     * @param _proposalId The ID of the proposal to vote on
     * @param _vote The vote (true = yes, false = no)
     */
    function voteProposal(uint256 _proposalId, bool _vote) public {
        if (!voters.contains(msg.sender)) revert InvalidCaller();
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
        if (!success) revert ExternalCallFailed(_getRevertMsg(res));
        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Counts the votes for a proposal and determines if quorum is met
     * @dev Uses non-truncating comparison: yesVotes * 100 >= QuorumThreshold * totalVoters
     * @param _proposalId The ID of the proposal to count votes for
     * @return yesVotes The total number of "yes" votes
     * @return hasQuorum Whether the proposal has enough votes to pass
     */
    function countVotes(uint256 _proposalId) public view returns (uint256 yesVotes, bool hasQuorum) {
        uint256 totalVoters = voters.length();
        for (uint256 i = 0; i < totalVoters; i++) {
            address voter = voters.at(i);
            if (getVote(_proposalId, voter)) yesVotes += 1;
        }
        hasQuorum = (yesVotes * 100) >= QuorumThreshold * totalVoters;
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
     * @return voterList The array of voter addresses
     */
    function getVoters() external view returns (address[] memory) {
        uint256 totalVoters = voters.length();
        address[] memory voterList = new address[](totalVoters);
        for (uint256 i = 0; i < totalVoters; i++) {
            voterList[i] = voters.at(i);
        }
        return voterList;
    }

    /**
     * @notice Extracts revert message from failed external call
     * @dev If no revert string is present, returns a generic message. Decodes standard Error(string).
     * @param _returnData The return data from the failed call
     * @return revertMessage The revert message string
     */
    function _getRevertMsg(bytes memory _returnData) private pure returns (string memory revertMessage) {
        // If the _returnData length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "Transaction reverted silently";
        assembly {
            // Slice the sighash
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }
}
