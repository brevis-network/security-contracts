// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title IGovernanceCouncil
 * @author Brevis Network
 * @notice Interface for the GovernanceCouncil governance contract
 */
interface IGovernanceCouncil {
    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                             ERRORS
    // ════════════════════════════════════════════════════════════════════════════════════════

    error InvalidLength();
    error InvalidActivePeriod();
    error InvalidProposalForwarder();
    error InvalidThreshold();
    error InvalidCaller();
    error InvalidSelector();
    error DeadlinePassed();
    error OnlyVoterCanCreateProposal();
    error OnlyVoterCanExecuteProposal();
    error DataHashMismatch();
    error NotEnoughVotes();
    error ZeroPower();
    error NotVoter();
    error FailedToSendNativeToken();
    error NoVotersRemaining();

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                            EVENTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    event Initiated(
        address[] voters, uint256[] powers, address[] forwarders, uint256 activePeriod, uint256 quorumThreshold
    );

    // Intentionally keep event fields unindexed (see README and interface docs) for readability and gas
    event ProposalCreated(uint256 proposalId, address target, bytes data, uint256 deadline, address proposer);
    event ProposalVoted(uint256 proposalId, address voter, bool vote);
    event ProposalExecuted(uint256 proposalId);

    // Parameter proposals (split by field)
    event ActivePeriodUpdateProposed(uint256 proposalId, uint256 newActivePeriod);
    event QuorumThresholdUpdateProposed(uint256 proposalId, uint256 newQuorumThreshold);
    event VoterUpdateProposed(uint256 proposalId, address[] voters, uint256[] powers);
    event ProposalForwarderUpdateProposed(uint256 proposalId, address[] addrs, bool[] ops);
    event TokenTransferProposed(uint256 proposalId, address receiver, address token, uint256 amount);
    event NativeTokenTransferGasUpdateProposed(uint256 proposalId, uint256 newGasLimit);

    // Execution-time granular state change events
    event ProposalForwarderUpdated(address forwarder, bool authorized);
    event ActivePeriodUpdated(uint256 oldValue, uint256 newValue);
    event QuorumThresholdUpdated(uint256 oldValue, uint256 newValue);
    event VoterUpdated(address voter, uint256 oldPower, uint256 newPower); // newPower == 0 => removed
    event TokenTransferred(address receiver, address token, uint256 amount);
    event NativeTokenTransferGasUpdated(uint256 oldGas, uint256 newGas);

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                   PROPOSAL CREATION FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Creates a new external proposal with default threshold requirements
     * @param _target The target contract address to call
     * @param _data The encoded function call data
     * @return proposalId The ID of the created proposal
     */
    function createProposal(address _target, bytes memory _data) external returns (uint256 proposalId);

    /**
     * @notice Creates a new proposal through a trusted proposal forwarder contract
     * @param _proposer The actual proposer (passed through by the forwarder)
     * @param _target The target contract address to call
     * @param _data The encoded function call data
     * @return proposalId The ID of the created proposal
     */
    function createProposal(address _proposer, address _target, bytes memory _data)
        external
        returns (uint256 proposalId);

    /**
     * @notice Creates a proposal to update the Active Period
     * @param _newActivePeriod New active period in seconds (must be within [MIN_ACTIVE_PERIOD, MAX_ACTIVE_PERIOD])
     * @return proposalId The ID of the created proposal
     */
    function proposeActivePeriodUpdate(uint256 _newActivePeriod) external returns (uint256 proposalId);

    /**
     * @notice Creates a proposal to update the Quorum Threshold (0 < threshold < 100)
     * @param _newQuorumThreshold New quorum threshold (percentage out of 100)
     * @return proposalId The ID of the created proposal
     */
    function proposeQuorumThresholdUpdate(uint256 _newQuorumThreshold) external returns (uint256 proposalId);

    /**
     * @notice Creates a proposal to update voter addresses and their voting powers
     * @param _voters Array of voter addresses to add/update (use power 0 to remove)
     * @param _powers Array of voting powers corresponding to each voter
     * @return proposalId The ID of the created proposal
     */
    function proposeVoterUpdate(address[] calldata _voters, uint256[] calldata _powers)
        external
        returns (uint256 proposalId);

    /**
     * @notice Creates a proposal to add or remove trusted proposal forwarder contracts
     * @param _addrs Array of forwarder contract addresses
     * @param _authorized Array of authorization status (true = authorize, false = revoke)
     * @return proposalId The ID of the created proposal
     */
    function proposeProposalForwarderUpdate(address[] calldata _addrs, bool[] calldata _authorized)
        external
        returns (uint256 proposalId);

    /**
     * @notice Creates a proposal to transfer tokens from the contract
     * @param _receiver The address to receive the tokens
     * @param _token The token contract address (use address(0) for native tokens)
     * @param _amount The amount of tokens to transfer
     * @return proposalId The ID of the created proposal
     */
    function proposeTokenTransfer(address _receiver, address _token, uint256 _amount)
        external
        returns (uint256 proposalId);

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                       VOTING FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Casts a vote on a proposal
     * @param _proposalId The ID of the proposal to vote on
     * @param _vote The vote (true = yes, false = no)
     */
    function voteProposal(uint256 _proposalId, bool _vote) external;

    /**
     * @notice Casts votes on multiple proposals in a single transaction
     * @param _proposalIds Array of proposal IDs to vote on
     * @param _votes Array of votes corresponding to each proposal
     */
    function voteProposals(uint256[] calldata _proposalIds, bool[] calldata _votes) external;

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                      PROPOSAL EXECUTION
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Executes a proposal if it has sufficient votes and is still active
     * @param _proposalId The ID of the proposal to execute
     * @param _type The type of the proposal (must match the original)
     * @param _target The target contract address (must match the original)
     * @param _data The encoded function call data (must match the original)
     */
    /**
     * @notice Executes a proposal if it has sufficient votes and is still active
     *         Threshold selection: always uses quorumThreshold.
     */
    function executeProposal(uint256 _proposalId, address _target, bytes calldata _data) external;

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                        VIEW FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns all voters and their voting powers
     * @return addrs Array of voter addresses
     * @return powers Array of voting powers corresponding to each address
     * @return totalPower The total voting power of all voters
     */
    function getVoters() external view returns (address[] memory addrs, uint256[] memory powers, uint256 totalPower);

    /**
     * @notice Returns the voting power of a specific voter
     * @param _voter The address of the voter to query
     * @return power The voting power of the voter (0 if not a voter)
     */
    function getVoterPower(address _voter) external view returns (uint256 power);

    /**
     * @notice Returns how a specific voter voted on a proposal
     * @param _proposalId The ID of the proposal to check
     * @param _voter The address of the voter to check
     * @return vote The vote cast by the voter (true = yes, false = no or no vote)
     */
    function getVote(uint256 _proposalId, address _voter) external view returns (bool vote);

    /**
     * @notice Counts the votes for a proposal (simplified version without threshold calculation)
     * @dev This function doesn't determine if the proposal passes since it doesn't know the proposal type
     * @param _proposalId The ID of the proposal to count votes for
     * @return totalPower The total voting power of all voters
     * @return yesVotes The total voting power of "yes" votes
     */

    /**
     * @notice Counts the votes for a proposal and determines if it passes, using a single quorum threshold
     * @param _proposalId The ID of the proposal to count votes for
     * @return totalPower The total voting power of all voters
     * @return yesVotes The total voting power of "yes" votes
     * @return pass Whether the proposal has enough votes to pass
     */
    function countVotes(uint256 _proposalId) external view returns (uint256 totalPower, uint256 yesVotes, bool pass);

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                        STATE VARIABLES
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Decimal precision for threshold calculations (represents 100%)
     */
    function THRESHOLD_DECIMAL() external view returns (uint256);

    /**
     * @notice Minimum allowed active period for proposals (1 hour)
     */
    function MIN_ACTIVE_PERIOD() external view returns (uint256);

    /**
     * @notice Maximum allowed active period for proposals (4 weeks)
     */
    function MAX_ACTIVE_PERIOD() external view returns (uint256);

    /**
     * @notice Mapping of parameter names to their current values
     */
    // Individual parameter getters
    function activePeriod() external view returns (uint256);

    function quorumThreshold() external view returns (uint256);

    /**
     * @notice Counter for generating unique proposal IDs
     */
    function nextProposalId() external view returns (uint256);

    /**
     * @notice Checks if an address is a trusted proposal forwarder
     * @param _forwarder The forwarder address to check
     * @return isTrusted True if the address is a trusted proposal forwarder, false otherwise
     */
    function isProposalForwarder(address _forwarder) external view returns (bool isTrusted);

    /**
     * @notice Returns all trusted proposal forwarder addresses
     * @return forwarders Array of all trusted proposal forwarder addresses
     */
    function getProposalForwarders() external view returns (address[] memory forwarders);

    /**
     * @notice Gas limit for native token transfers to prevent griefing attacks
     */
    function nativeTokenTransferGas() external view returns (uint256);
}
