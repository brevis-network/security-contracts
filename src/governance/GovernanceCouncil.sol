// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IGovernanceCouncil.sol";

/**
 * @title GovernanceCouncil
 * @author Brevis Network
 * @notice A multi-signature governance contract for managing protocol operations
 * @dev This contract is designed for infrequent governance operations with multiple voters.
 *      It prioritizes ease of use over gas efficiency and supports various proposal types
 *      including external calls, parameter changes, voter management, and token transfers.
 *
 * Key Features:
 * - Voter-based governance with configurable voting powers
 * - Multiple proposal types with different approval thresholds
 * - Support for trusted proposal forwarder contracts
 * - Built-in reentrancy protection
 * - Flexible token transfer capabilities (ERC20 and native tokens)
 */
contract GovernanceCouncil is IGovernanceCouncil {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============================================================================================
    // CONSTANTS
    // ============================================================================================

    /// @notice Decimal precision for threshold calculations (represents 100%)
    uint256 public constant THRESHOLD_DECIMAL = 100;

    /// @notice Minimum allowed active period for proposals (1 hour)
    uint256 public constant MIN_ACTIVE_PERIOD = 3600;

    /// @notice Maximum allowed active period for proposals (4 weeks)
    uint256 public constant MAX_ACTIVE_PERIOD = 2419200;

    // ============================================================================================
    // STATE VARIABLES
    // ============================================================================================

    /// Active period for proposals (seconds)
    uint256 public activePeriod;

    /// Quorum threshold (percentage out of 100)
    uint256 public quorumThreshold;

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

    /// EnumerableMap storing voter addresses and their voting powers
    EnumerableMap.AddressToUintMap private voters;

    /// Addresses that are trusted to create proposals on behalf of others
    /// NOTE: Proposal forwarders must be audited open-source non-upgradable contracts that
    /// truthfully pass along tx sender who called the propose function.
    /// See ./proposal-forwarders/AccessControlForwarder.sol for example.
    EnumerableSet.AddressSet proposerForwarders;

    /// Gas limit for native token transfers to prevent griefing attacks
    uint256 public nativeTokenTransferGas = 50000;

    // ============================================================================================
    // CONSTRUCTOR
    // ============================================================================================

    /**
     * @notice Initializes the GovernanceCouncil with voters, forwarders, and governance parameters
     * @param _voters Array of initial voter addresses
     * @param _powers Array of voting powers corresponding to each voter
     * @param _forwarders Array of trusted proposal forwarder contract addresses
     * @param _activePeriod Duration (in seconds) for which proposals remain active
     * @param _quorumThreshold Percentage threshold for proposals (out of 100)
     */
    constructor(
        address[] memory _voters,
        uint256[] memory _powers,
        address[] memory _forwarders,
        uint256 _activePeriod,
        uint256 _quorumThreshold
    ) {
        if (_voters.length == 0 || _voters.length != _powers.length) revert InvalidLength();
        if (_activePeriod > MAX_ACTIVE_PERIOD || _activePeriod < MIN_ACTIVE_PERIOD) revert InvalidActivePeriod();
        if (_quorumThreshold >= THRESHOLD_DECIMAL || _quorumThreshold == 0) {
            revert InvalidThreshold();
        }
        for (uint256 i = 0; i < _voters.length; i++) {
            if (_powers[i] == 0) revert ZeroPower();
            voters.set(_voters[i], _powers[i]);
        }
        for (uint256 i = 0; i < _forwarders.length; i++) {
            proposerForwarders.add(_forwarders[i]);
        }
        activePeriod = _activePeriod;
        quorumThreshold = _quorumThreshold;
        emit Initiated(_voters, _powers, _forwarders, _activePeriod, _quorumThreshold);
    }

    // ============================================================================================
    // PROPOSAL CREATION
    // ============================================================================================

    /**
     * @notice Creates a new proposal
     * @param _target The target contract address to call
     * @param _data The encoded function call data
     * @return proposalId The ID of the created proposal
     */
    function createProposal(address _target, bytes calldata _data) public returns (uint256 proposalId) {
        if (_data.length < 4) revert InvalidSelector();
        return _createProposal(msg.sender, _target, _data);
    }

    /**
     * @notice Batch creates proposals
     * @param _targets The target contract address to call
     * @param _datas The encoded function call data
     * @return proposalIds The IDs of the created proposals
     */
    function createProposals(address[] calldata _targets, bytes[] calldata _datas)
        external
        returns (uint256[] memory proposalIds)
    {
        uint256 numProposals = _targets.length;
        if (numProposals != _datas.length) revert InvalidLength();
        proposalIds = new uint256[](numProposals);
        for (uint256 i = 0; i < numProposals; i++) {
            proposalIds[i] = createProposal(_targets[i], _datas[i]);
        }
        return proposalIds;
    }

    /**
     * @notice Creates a new proposal through a trusted proposal forwarder contract
     * @param _proposer The actual proposer (passed through by the forwarder)
     * @param _target The target contract address to call
     * @param _data The encoded function call data
     * @return proposalId The ID of the created proposal
     */
    function createProposal(address _proposer, address _target, bytes calldata _data)
        external
        returns (uint256 proposalId)
    {
        if (!proposerForwarders.contains(msg.sender)) revert InvalidProposalForwarder();
        if (_data.length < 4) revert InvalidSelector();
        return _createProposal(_proposer, _target, _data);
    }

    /**
     * @notice Creates a proposal to update the Active Period parameter
     * @param _newActivePeriod The new active period (in seconds)
     * @return proposalId The ID of the created proposal
     */
    function proposeActivePeriodUpdate(uint256 _newActivePeriod) external returns (uint256 proposalId) {
        bytes memory data = abi.encodeCall(this.updateActivePeriod, (_newActivePeriod));
        proposalId = _createProposal(msg.sender, address(this), data);
        emit ActivePeriodUpdateProposed(proposalId, _newActivePeriod);
    }

    /**
     * @notice Creates a proposal to update the Quorum Threshold parameter
     * @param _newQuorumThreshold The new quorum threshold (percentage out of 100)
     * @return proposalId The ID of the created proposal
     */
    function proposeQuorumThresholdUpdate(uint256 _newQuorumThreshold) external returns (uint256 proposalId) {
        bytes memory data = abi.encodeCall(this.updateQuorumThreshold, (_newQuorumThreshold));
        proposalId = _createProposal(msg.sender, address(this), data);
        emit QuorumThresholdUpdateProposed(proposalId, _newQuorumThreshold);
    }

    /**
     * @notice Creates a proposal to update voter addresses and their voting powers
     * @param _voters Array of voter addresses to add/update (use power 0 to remove)
     * @param _powers Array of voting powers corresponding to each voter
     * @return proposalId The ID of the created proposal
     */
    function proposeVoterUpdate(address[] calldata _voters, uint256[] calldata _powers)
        external
        returns (uint256 proposalId)
    {
        if (_voters.length != _powers.length) revert InvalidLength();
        bytes memory data = abi.encodeCall(this.updateVoters, (_voters, _powers));
        proposalId = _createProposal(msg.sender, address(this), data);
        emit VoterUpdateProposed(proposalId, _voters, _powers);
    }

    /**
     * @notice Creates a proposal to add or remove trusted proposal forwarder contracts
     * @param _addrs Array of forwarder contract addresses
     * @param _authorized Array of authorization status (true = authorize, false = revoke)
     * @return proposalId The ID of the created proposal
     */
    function proposeProposalForwarderUpdate(address[] calldata _addrs, bool[] calldata _authorized)
        external
        returns (uint256 proposalId)
    {
        if (_addrs.length != _authorized.length) revert InvalidLength();
        bytes memory data = abi.encodeCall(this.updateProposalForwarders, (_addrs, _authorized));
        proposalId = _createProposal(msg.sender, address(this), data);
        emit ProposalForwarderUpdateProposed(proposalId, _addrs, _authorized);
    }

    /**
     * @notice Creates a proposal to transfer tokens from the contract
     * @param _receiver The address to receive the tokens
     * @param _token The token contract address (use address(0) for native tokens)
     * @param _amount The amount of tokens to transfer
     * @return proposalId The ID of the created proposal
     */
    function proposeTokenTransfer(address _receiver, address _token, uint256 _amount)
        external
        returns (uint256 proposalId)
    {
        bytes memory data;
        address target = address(this);
        if (_token == address(0)) {
            data = abi.encodeCall(this.transferNative, (payable(_receiver), _amount));
        } else {
            data = abi.encodeCall(this.transferERC20, (_token, _receiver, _amount));
        }
        proposalId = _createProposal(msg.sender, target, data);
        emit TokenTransferProposed(proposalId, _receiver, _token, _amount);
    }

    /**
     * @notice Creates a proposal to update the native token transfer gas limit
     * @param _newGasLimit The new gas limit for native token transfers
     * @return proposalId The ID of the created proposal
     */
    function proposeNativeTokenTransferGasUpdate(uint256 _newGasLimit) external returns (uint256 proposalId) {
        bytes memory data = abi.encodeCall(this.updateNativeTokenTransferGas, (_newGasLimit));
        proposalId = _createProposal(msg.sender, address(this), data);
        emit NativeTokenTransferGasUpdateProposed(proposalId, _newGasLimit);
    }

    /**
     * @notice Creates a proposal and automatically votes yes for the proposer
     * @param _proposer The address of the proposer
     * @param _target The target contract address for the proposal
     * @param _data The encoded function call data
     * @return proposalId The ID of the created proposal
     */
    function _createProposal(address _proposer, address _target, bytes memory _data)
        private
        returns (uint256 proposalId)
    {
        if (!voters.contains(_proposer)) revert OnlyVoterCanCreateProposal();
        proposalId = nextProposalId;
        nextProposalId += 1;
        Proposal storage p = proposals[proposalId];
        p.dataHash = keccak256(abi.encodePacked(_target, _data));
        p.deadline = block.timestamp + activePeriod;
        p.votes[_proposer] = true;
        emit ProposalCreated(proposalId, _target, _data, p.deadline, _proposer);
    }

    // ============================================================================================
    // VOTING
    // ============================================================================================

    /**
     * @notice Casts a vote on a proposal
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
     * @notice Casts votes on multiple proposals in a single transaction
     * @param _proposalIds Array of proposal IDs to vote on
     * @param _votes Array of votes corresponding to each proposal
     */
    function voteProposals(uint256[] calldata _proposalIds, bool[] calldata _votes) external {
        if (_proposalIds.length != _votes.length) revert InvalidLength();
        for (uint256 i = 0; i < _proposalIds.length; i++) {
            voteProposal(_proposalIds[i], _votes[i]);
        }
    }

    // ============================================================================================
    // PROPOSAL EXECUTION
    // ============================================================================================

    /**
     * @notice Executes a proposal if it has sufficient votes and is still active
     * @param _proposalId The ID of the proposal to execute
     * @param _target The target contract address (must match the original)
     * @param _data The encoded function call data (must match the original)
     */
    function executeProposal(uint256 _proposalId, address _target, bytes calldata _data) public {
        if (!voters.contains(msg.sender)) revert OnlyVoterCanExecuteProposal();
        Proposal storage p = proposals[_proposalId];
        if (block.timestamp >= p.deadline) revert DeadlinePassed();
        if (keccak256(abi.encodePacked(_target, _data)) != p.dataHash) revert DataHashMismatch();

        // Prevent reentrancy by setting deadline to 0 before external calls
        p.deadline = 0;

        // Executor automatically votes yes
        p.votes[msg.sender] = true;
        (,, bool pass) = countVotes(_proposalId);
        if (!pass) revert NotEnoughVotes();

        // Execute external call (self-targeted calls go through onlySelf gates)
        (bool success, bytes memory res) = _target.call(_data);
        if (!success) {
            assembly {
                revert(add(res, 0x20), mload(res))
            }
        }
        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Batch executes proposals
     * @param _proposalIds The IDs of the proposals to execute
     * @param _targets The target contract addresses (must match the original)
     * @param _datas The encoded function call datas (must match the original)
     */
    function executeProposals(uint256[] calldata _proposalIds, address[] calldata _targets, bytes[] calldata _datas)
        external
    {
        if (_proposalIds.length != _targets.length || _proposalIds.length != _datas.length) {
            revert InvalidLength();
        }
        for (uint256 i = 0; i < _proposalIds.length; i++) {
            executeProposal(_proposalIds[i], _targets[i], _datas[i]);
        }
    }

    // ============================================================================================
    // ONLY-SELF GOVERNANCE ACTIONS
    // ============================================================================================

    modifier onlySelf() {
        require(msg.sender == address(this), "onlySelf");
        _;
    }

    /**
     * @notice Update a governance parameter
     */
    function updateActivePeriod(uint256 value) external onlySelf {
        if (value > MAX_ACTIVE_PERIOD || value < MIN_ACTIVE_PERIOD) revert InvalidActivePeriod();
        uint256 old = activePeriod;
        activePeriod = value;
        emit ActivePeriodUpdated(old, value);
    }

    /**
     * @notice Update a governance parameter
     */
    function updateQuorumThreshold(uint256 value) external onlySelf {
        if (value >= THRESHOLD_DECIMAL || value == 0) revert InvalidThreshold();
        uint256 old = quorumThreshold;
        quorumThreshold = value;
        emit QuorumThresholdUpdated(old, value);
    }

    /**
     * @notice Update voters and their powers (0 power removes)
     */
    function updateVoters(address[] calldata addrs, uint256[] calldata powers) external onlySelf {
        for (uint256 i = 0; i < addrs.length; i++) {
            (bool exists, uint256 oldPower) = voters.tryGet(addrs[i]);
            if (powers[i] > 0) {
                voters.set(addrs[i], powers[i]);
                emit VoterUpdated(addrs[i], exists ? oldPower : 0, powers[i]);
            } else if (exists) {
                voters.remove(addrs[i]);
                emit VoterUpdated(addrs[i], oldPower, 0);
            }
        }
        if (voters.length() == 0) revert NoVotersRemaining();
    }

    /**
     * @notice Update proposal forwarders
     */
    function updateProposalForwarders(address[] calldata addrs, bool[] calldata ops) external onlySelf {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (ops[i]) {
                proposerForwarders.add(addrs[i]);
            } else {
                proposerForwarders.remove(addrs[i]);
            }
            emit ProposalForwarderUpdated(addrs[i], ops[i]);
        }
    }

    /**
     * @notice Transfer native token
     */
    function transferNative(address payable receiver, uint256 amount) external onlySelf {
        (bool sent,) = receiver.call{value: amount, gas: nativeTokenTransferGas}("");
        if (!sent) revert FailedToSendNativeToken();
        emit TokenTransferred(receiver, address(0), amount);
    }

    /**
     * @notice Transfer ERC20 token
     */
    function transferERC20(address token, address receiver, uint256 amount) external onlySelf {
        IERC20(token).safeTransfer(receiver, amount);
        emit TokenTransferred(receiver, token, amount);
    }

    /**
     * @notice Sets the gas limit for native token transfers to prevent griefing attacks
     * @param _gasUsed The gas limit to use for native token transfers
     */
    function updateNativeTokenTransferGas(uint256 _gasUsed) external onlySelf {
        uint256 old = nativeTokenTransferGas;
        nativeTokenTransferGas = _gasUsed;
        emit NativeTokenTransferGasUpdated(old, _gasUsed);
    }

    /**
     * @notice Allows the contract to receive native tokens
     */
    receive() external payable {}

    // ============================================================================================
    // VIEW FUNCTIONS
    // ============================================================================================

    /**
     * @notice Returns all voters and their voting powers
     * @return addrs Array of voter addresses
     * @return powers Array of voting powers corresponding to each address
     * @return totalPower The total voting power of all voters
     */
    function getVoters() public view returns (address[] memory addrs, uint256[] memory powers, uint256 totalPower) {
        uint256 length = voters.length();
        addrs = new address[](length);
        powers = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            (addrs[i], powers[i]) = voters.at(i);
            totalPower += powers[i];
        }
    }

    /**
     * @notice Returns the voting power of a specific voter
     * @param _voter The address of the voter to query
     * @return power The voting power of the voter (0 if not a voter)
     */
    function getVoterPower(address _voter) public view returns (uint256 power) {
        bool exists;
        (exists, power) = voters.tryGet(_voter);
        if (!exists) {
            power = 0;
        }
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
     * @notice Counts the votes for a proposal and determines if it passes, using a single quorum threshold
     * @param _proposalId The ID of the proposal to count votes for
     * @return totalPower The total voting power of all voters
     * @return yesVotes The total voting power of "yes" votes
     * @return pass Whether the proposal has enough votes to pass
     */
    function countVotes(uint256 _proposalId) public view returns (uint256 totalPower, uint256 yesVotes, bool pass) {
        uint256 length = voters.length();
        for (uint256 i = 0; i < length; i++) {
            (address voter, uint256 power) = voters.at(i);
            if (getVote(_proposalId, voter)) yesVotes += power;
            totalPower += power;
        }
        uint256 threshold = quorumThreshold;
        pass = (yesVotes >= (totalPower * threshold) / THRESHOLD_DECIMAL);
    }

    /**
     * @notice Checks if an address is a trusted proposal forwarder
     * @param _forwarder The forwarder address to check
     * @return isTrusted True if the address is a trusted proposal forwarder, false otherwise
     */
    function isProposalForwarder(address _forwarder) public view returns (bool isTrusted) {
        return proposerForwarders.contains(_forwarder);
    }

    /**
     * @notice Returns all trusted proposal forwarder addresses
     * @return forwarders Array of all trusted proposal forwarder addresses
     */
    function getProposalForwarders() public view returns (address[] memory forwarders) {
        return proposerForwarders.values();
    }
}
