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
    error InvalidInitThresholds();
    error InvalidProposalForwarder();
    error InvalidProposalType();
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
    //                                             ENUMS
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Parameters that can be modified through governance proposals
     */
    enum Param {
        // Duration for which proposals remain active
        ActivePeriod,
        // Threshold for proposals to pass
        QuorumThreshold,
        // Lower threshold for less critical operations
        FastPassThreshold
    }

    /**
     * @notice Types of proposals supported by the governance system
     */
    enum ProposalType {
        // External contract calls (threshold auto-detected based on fast-pass authorization)
        External,
        // Update governance parameters
        ParamUpdate,
        // Adding/removing/updating voters
        VoterUpdate,
        // Adding/removing proposer proposal forwarder contracts
        ProposalForwarderUpdate,
        // Adding/removing fast-pass authorizations
        FastPassUpdate,
        // Token transfers from the contract
        TokenTransfer
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                            EVENTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    event Initiated(
        address[] voters,
        uint256[] powers,
        address[] forwarders,
        uint256 activePeriod,
        uint256 quorumThreshold,
        uint256 fastPassThreshold
    );

    event ProposalCreated(
        uint256 proposalId, ProposalType proposalType, address target, bytes data, uint256 deadline, address proposer
    );
    event ProposalVoted(uint256 proposalId, address voter, bool vote);
    event ProposalExecuted(uint256 proposalId);

    event ParamUpdateProposed(uint256 proposalId, Param name, uint256 value);
    event VoterUpdateProposed(uint256 proposalId, address[] voters, uint256[] powers);
    event ProposalForwarderUpdateProposed(uint256 proposalId, address[] addrs, bool[] ops);
    event FastPassUpdateProposed(uint256 proposalId, address[] targets, bytes4[] selectors, bool[] authorized);
    event TokenTransferProposed(uint256 proposalId, address receiver, address token, uint256 amount);
    event NativeTokenTransferGasUpdated(uint256 oldGas, uint256 newGas);

    // Execution-time granular state change events
    event ProposalForwarderUpdated(address forwarder, bool authorized);
    event FastPassAuthorizationUpdated(address target, bytes4 selector, bool authorized);
    event ParamUpdated(Param name, uint256 oldValue, uint256 newValue);
    event VoterUpdated(address voter, uint256 oldPower, uint256 newPower); // newPower == 0 => removed
    event TokenTransferred(address receiver, address token, uint256 amount);
    event ExternalCallExecuted(address target, bytes4 selector);

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
     * @notice Creates a proposal to change a governance parameter
     * @param _name The parameter to change
     * @param _value The new value for the parameter
     * @return proposalId The ID of the created proposal
     */
    function proposeParamUpdate(Param _name, uint256 _value) external returns (uint256 proposalId);

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
     * @notice Creates a proposal to add or remove fast-pass authorizations
     * @param _targets Array of target contract addresses
     * @param _selectors Array of function selectors (use bytes4(0) for all functions)
     * @param _authorized Array of authorization status (true = authorize, false = revoke)
     * @return proposalId The ID of the created proposal
     */
    function proposeFastPassUpdate(
        address[] calldata _targets,
        bytes4[] calldata _selectors,
        bool[] calldata _authorized
    ) external returns (uint256 proposalId);

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
    function executeProposal(uint256 _proposalId, ProposalType _type, address _target, bytes calldata _data) external;

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                   CONFIGURATION FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets the gas limit for native token transfers to prevent griefing attacks
     * @param _gasUsed The gas limit to use for native token transfers
     */
    function setNativeTokenTransferGas(uint256 _gasUsed) external;

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
    function countVotes(uint256 _proposalId) external view returns (uint256 totalPower, uint256 yesVotes);

    /**
     * @notice Counts the votes for a proposal and determines if it passes
     * @param _proposalId The ID of the proposal to count votes for
     * @param _type The type of the proposal (affects threshold calculation)
     * @param _target The target contract address (only used for External proposals)
     * @param _selector The function selector (only used for External proposals)
     * @return totalPower The total voting power of all voters
     * @return yesVotes The total voting power of "yes" votes
     * @return pass Whether the proposal has enough votes to pass
     */
    function countVotes(uint256 _proposalId, ProposalType _type, address _target, bytes4 _selector)
        external
        view
        returns (uint256 totalPower, uint256 yesVotes, bool pass);

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
    function params(Param) external view returns (uint256);

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
     * @notice Checks if a specific function on a target is authorized for fast-pass
     * @param _target The target contract address
     * @param _selector The function selector (use bytes4(0) to check for wildcard)
     * @return isAuthorized True if the function is authorized for fast-pass
     */
    function isFastPassAuthorized(address _target, bytes4 _selector) external view returns (bool isAuthorized);

    /**
     * @notice Returns all fast-pass authorization keys (packed target+selector)
     * @return authKeys Array of all authorization keys (bytes32 packed: high 160 bits target, low 32 bits selector)
     */
    function getFastPassAuthorizations() external view returns (bytes32[] memory authKeys);

    /**
     * @notice Gas limit for native token transfers to prevent griefing attacks
     */
    function nativeTokenTransferGas() external view returns (uint256);
}
