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
    using EnumerableSet for EnumerableSet.Bytes32Set;

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

    /// Mapping of parameter names to their current values
    mapping(Param => uint256) public params;

    /// Proposal data structure containing hash, deadline, and votes
    struct Proposal {
        bytes32 dataHash; // keccak256(abi.encodePacked(_type, _target, _data))
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

    /// Fast-pass authorization mapping using a reversible packed key:
    /// key = bytes32( (uint256(uint160(target)) << 32) | uint32(selector) )
    /// - High 160 bits: target address
    /// - Low 32 bits: function selector (bytes4)
    /// Use selector = bytes4(0) to wildcard all functions on a target.
    EnumerableSet.Bytes32Set authorizedFastPass;

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
     * @param _quorumThreshold Percentage threshold for regular proposals (out of 100)
     * @param _fastPassThreshold Percentage threshold for fast-pass proposals (out of 100)
     */
    constructor(
        address[] memory _voters,
        uint256[] memory _powers,
        address[] memory _forwarders,
        uint256 _activePeriod,
        uint256 _quorumThreshold,
        uint256 _fastPassThreshold
    ) {
        if (_voters.length == 0 || _voters.length != _powers.length) revert InvalidLength();
        if (_activePeriod > MAX_ACTIVE_PERIOD || _activePeriod < MIN_ACTIVE_PERIOD) revert InvalidActivePeriod();
        if (_quorumThreshold >= THRESHOLD_DECIMAL || _fastPassThreshold > _quorumThreshold) {
            revert InvalidThreshold();
        }
        for (uint256 i = 0; i < _voters.length; i++) {
            _setVoter(_voters[i], _powers[i]);
        }
        for (uint256 i = 0; i < _forwarders.length; i++) {
            proposerForwarders.add(_forwarders[i]);
        }
        params[Param.ActivePeriod] = _activePeriod;
        params[Param.QuorumThreshold] = _quorumThreshold;
        params[Param.FastPassThreshold] = _fastPassThreshold;
        emit Initiated(_voters, _powers, _forwarders, _activePeriod, _quorumThreshold, _fastPassThreshold);
    }

    // ============================================================================================
    // PROPOSAL CREATION
    // ============================================================================================

    /**
     * @notice Creates a new external proposal with auto-detected threshold
     * @param _target The target contract address to call
     * @param _data The encoded function call data
     * @return proposalId The ID of the created proposal
     */
    function createProposal(address _target, bytes calldata _data) public returns (uint256 proposalId) {
        if (_data.length < 4) revert InvalidSelector();
        return _createProposal(msg.sender, _target, _data, ProposalType.External);
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
        return _createProposal(_proposer, _target, _data, ProposalType.External);
    }

    /**
     * @notice Creates a proposal to change a governance parameter
     * @param _name The parameter to change
     * @param _value The new value for the parameter
     * @return proposalId The ID of the created proposal
     */
    function proposeParamUpdate(Param _name, uint256 _value) external returns (uint256 proposalId) {
        bytes memory data = abi.encode(_name, _value);
        proposalId = _createProposal(msg.sender, address(0), data, ProposalType.ParamUpdate);
        emit ParamUpdateProposed(proposalId, _name, _value);
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
        bytes memory data = abi.encode(_voters, _powers);
        proposalId = _createProposal(msg.sender, address(0), data, ProposalType.VoterUpdate);
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
        bytes memory data = abi.encode(_addrs, _authorized);
        proposalId = _createProposal(msg.sender, address(0), data, ProposalType.ProposalForwarderUpdate);
        emit ProposalForwarderUpdateProposed(proposalId, _addrs, _authorized);
    }

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
    ) external returns (uint256 proposalId) {
        if (_targets.length != _selectors.length || _targets.length != _authorized.length) revert InvalidLength();
        bytes memory data = abi.encode(_targets, _selectors, _authorized);
        proposalId = _createProposal(msg.sender, address(0), data, ProposalType.FastPassUpdate);
        emit FastPassUpdateProposed(proposalId, _targets, _selectors, _authorized);
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
        bytes memory data = abi.encode(_receiver, _token, _amount);
        proposalId = _createProposal(msg.sender, address(0), data, ProposalType.TokenTransfer);
        emit TokenTransferProposed(proposalId, _receiver, _token, _amount);
    }

    /**
     * @notice Creates a proposal and automatically votes yes for the proposer
     * @param _proposer The address of the proposer
     * @param _target The target contract address for the proposal
     * @param _data The encoded function call data
     * @param _type The type of the proposal
     * @return proposalId The ID of the created proposal
     */
    function _createProposal(address _proposer, address _target, bytes memory _data, ProposalType _type)
        private
        returns (uint256 proposalId)
    {
        if (!voters.contains(_proposer)) revert OnlyVoterCanCreateProposal();
        proposalId = nextProposalId;
        nextProposalId += 1;
        Proposal storage p = proposals[proposalId];
        p.dataHash = keccak256(abi.encodePacked(_type, _target, _data));
        p.deadline = block.timestamp + params[Param.ActivePeriod];
        p.votes[_proposer] = true;
        emit ProposalCreated(proposalId, _type, _target, _data, p.deadline, _proposer);
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
     * @param _type The type of the proposal (must match the original)
     * @param _target The target contract address (must match the original)
     * @param _data The encoded function call data (must match the original)
     */
    function executeProposal(uint256 _proposalId, ProposalType _type, address _target, bytes calldata _data) public {
        if (!voters.contains(msg.sender)) revert OnlyVoterCanExecuteProposal();
        Proposal storage p = proposals[_proposalId];
        if (block.timestamp >= p.deadline) revert DeadlinePassed();
        if (keccak256(abi.encodePacked(_type, _target, _data)) != p.dataHash) revert DataHashMismatch();

        // Prevent reentrancy by setting deadline to 0 before external calls
        p.deadline = 0;

        // Executor automatically votes yes
        p.votes[msg.sender] = true;
        (,, bool pass) = countVotes(_proposalId, _type, _target, bytes4(_data[:4]));
        if (!pass) revert NotEnoughVotes();

        // Execute the proposal based on its type
        _executeProposalByType(_type, _target, _data);
        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Batch executes proposals
     * @param _proposalIds The IDs of the proposals to execute
     * @param _types The types of the proposals (must match the original)
     * @param _targets The target contract addresses (must match the original)
     * @param _datas The encoded function call datas (must match the original)
     */
    function executeProposals(
        uint256[] calldata _proposalIds,
        ProposalType[] calldata _types,
        address[] calldata _targets,
        bytes[] calldata _datas
    ) external {
        uint256 numProposals = _proposalIds.length;
        if (numProposals != _types.length || numProposals != _targets.length || numProposals != _datas.length) {
            revert InvalidLength();
        }
        for (uint256 i = 0; i < numProposals; i++) {
            executeProposal(_proposalIds[i], _types[i], _targets[i], _datas[i]);
        }
    }

    /**
     * @notice Executes proposal based on its type
     * @param _type The type of proposal to execute
     * @param _target The target address for external proposals
     * @param _data The proposal data
     */
    function _executeProposalByType(ProposalType _type, address _target, bytes calldata _data) private {
        if (_type == ProposalType.External) {
            _executeExternal(_target, _data);
        } else if (_type == ProposalType.ParamUpdate) {
            _executeParamUpdate(_data);
        } else if (_type == ProposalType.VoterUpdate) {
            _executeVoterUpdate(_data);
        } else if (_type == ProposalType.ProposalForwarderUpdate) {
            _executeProposalForwarderUpdate(_data);
        } else if (_type == ProposalType.FastPassUpdate) {
            _executeFastPassUpdate(_data);
        } else if (_type == ProposalType.TokenTransfer) {
            _executeTokenTransfer(_data);
        }
    }

    /**
     * @notice Executes external proposal (contract call)
     */
    function _executeExternal(address _target, bytes calldata _data) private {
        (bool success, bytes memory res) = _target.call(_data);
        if (!success) revert ExternalCallFailed(_getRevertMsg(res));
        bytes4 selector = _data.length >= 4 ? bytes4(_data[:4]) : bytes4(0);
        emit ExternalCallExecuted(_target, selector);
    }

    /**
     * @notice Executes parameter change proposal
     */
    function _executeParamUpdate(bytes calldata _data) private {
        (Param name, uint256 value) = abi.decode(_data, (Param, uint256));
        uint256 old = params[name];
        params[name] = value;
        if (name == Param.ActivePeriod) {
            if (value > MAX_ACTIVE_PERIOD || value < MIN_ACTIVE_PERIOD) revert InvalidActivePeriod();
        } else if (
            params[Param.QuorumThreshold] < params[Param.FastPassThreshold] || value >= THRESHOLD_DECIMAL || value == 0
        ) {
            revert InvalidThreshold();
        }
        emit ParamUpdated(name, old, value);
    }

    /**
     * @notice Executes voter update proposal
     */
    function _executeVoterUpdate(bytes calldata _data) private {
        (address[] memory addrs, uint256[] memory powers) = abi.decode(_data, (address[], uint256[]));
        for (uint256 i = 0; i < addrs.length; i++) {
            (bool exists, uint256 oldPower) = voters.tryGet(addrs[i]);
            if (powers[i] > 0) {
                _setVoter(addrs[i], powers[i]);
                emit VoterUpdated(addrs[i], exists ? oldPower : 0, powers[i]);
            } else {
                if (exists) {
                    _removeVoter(addrs[i]);
                    emit VoterUpdated(addrs[i], oldPower, 0);
                }
            }
        }
        if (voters.length() == 0) revert NoVotersRemaining();
    }

    /**
     * @notice Executes forwarder update proposal
     */
    function _executeProposalForwarderUpdate(bytes calldata _data) private {
        (address[] memory addrs, bool[] memory ops) = abi.decode(_data, (address[], bool[]));
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
     * @notice Executes fast-pass authorization update proposal
     */
    function _executeFastPassUpdate(bytes calldata _data) private {
        (address[] memory targets, bytes4[] memory selectors, bool[] memory authorized) =
            abi.decode(_data, (address[], bytes4[], bool[]));
        for (uint256 i = 0; i < targets.length; i++) {
            bytes32 key = _packFastPassKey(targets[i], selectors[i]);
            if (authorized[i]) {
                authorizedFastPass.add(key);
            } else {
                authorizedFastPass.remove(key);
            }
            emit FastPassAuthorizationUpdated(targets[i], selectors[i], authorized[i]);
        }
    }

    /**
     * @notice Executes token transfer proposal
     */
    function _executeTokenTransfer(bytes calldata _data) private {
        (address receiver, address token, uint256 amount) = abi.decode(_data, (address, address, uint256));
        if (token == address(0)) {
            (bool sent,) = receiver.call{value: amount, gas: nativeTokenTransferGas}("");
            if (!sent) revert FailedToSendNativeToken();
        } else {
            IERC20(token).safeTransfer(receiver, amount);
        }
        emit TokenTransferred(receiver, token, amount);
    }

    // ============================================================================================
    // CONFIGURATION
    // ============================================================================================

    /**
     * @notice Sets the gas limit for native token transfers to prevent griefing attacks
     * @param _gasUsed The gas limit to use for native token transfers
     */
    function setNativeTokenTransferGas(uint256 _gasUsed) external {
        if (!voters.contains(msg.sender)) revert InvalidCaller();
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
     * @notice Counts the votes for a proposal (simplified version without threshold calculation)
     * @dev This function doesn't determine if the proposal passes since it doesn't know the proposal type
     * @param _proposalId The ID of the proposal to count votes for
     * @return totalPower The total voting power of all voters
     * @return yesVotes The total voting power of "yes" votes
     */
    function countVotes(uint256 _proposalId) public view returns (uint256 totalPower, uint256 yesVotes) {
        uint256 length = voters.length();
        for (uint256 i = 0; i < length; i++) {
            (address voter, uint256 power) = voters.at(i);
            if (getVote(_proposalId, voter)) yesVotes += power;
            totalPower += power;
        }
    }

    /**
     * @notice Counts the votes for a proposal and determines if it passes
     * @dev Threshold classification for External proposals is evaluated only at execution;
     *      changes in fast-pass authorization after creation affect required votes.
     *
     * @param _proposalId The ID of the proposal to count votes for
     * @param _type The type of the proposal (affects threshold calculation)
     * @param _target The target contract address (only used for External proposals)
     * @param _selector The function selector (only used for External proposals)
     * @return totalPower The total voting power of all voters
     * @return yesVotes The total voting power of "yes" votes
     * @return pass Whether the proposal has enough votes to pass
     */
    function countVotes(uint256 _proposalId, ProposalType _type, address _target, bytes4 _selector)
        public
        view
        returns (uint256 totalPower, uint256 yesVotes, bool pass)
    {
        // Use the simplified version to get vote counts
        (totalPower, yesVotes) = countVotes(_proposalId);

        // Determine threshold based on proposal type and authorization
        uint256 threshold;
        if (_type == ProposalType.External) {
            // Auto-detect if fast-pass is authorized for this function
            if (isFastPassAuthorized(_target, _selector)) {
                threshold = params[Param.FastPassThreshold];
            } else {
                threshold = params[Param.QuorumThreshold];
            }
        } else {
            threshold = params[Param.QuorumThreshold];
        }

        // NOTE: rounding: yesVotes * 100 >= totalPower * threshold.
        // Example: 5 x 10k power humans + machine (power 1) => machine presence/vote doesn't change 3-of-5 human quorum.
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

    /**
     * @notice Checks if a specific function on a target is authorized for fast-pass
     * @param _target The target contract address
     * @param _selector The function selector (use bytes4(0) to check for wildcard)
     * @return isAuthorized True if the function is authorized for fast-pass
     */
    function isFastPassAuthorized(address _target, bytes4 _selector) public view returns (bool isAuthorized) {
        bytes32 key = _packFastPassKey(_target, _selector);
        if (authorizedFastPass.contains(key)) return true;
        // Check wildcard (selector = 0x00000000)
        bytes32 wildcardKey = _packFastPassKey(_target, bytes4(0));
        return authorizedFastPass.contains(wildcardKey);
    }

    /**
     * @notice Returns all fast-pass authorization keys
     * @return authKeys Array of all authorization keys. See {_packFastPassKey}.
     */
    function getFastPassAuthorizations() public view returns (bytes32[] memory authKeys) {
        return authorizedFastPass.values();
    }

    // ============================================================================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================================================================

    /**
     * @notice Packs (target, selector) into a reversible bytes32 key used in `authorizedFastPass`.
     * Layout (left -> right / high -> low bits): [ 64 bits zero ][ 160 bits target ][ 32 bits selector ]
     * Example:
     *   target   = 0x1234567890Abcdef1234567890abCdef12345678
     *   selector = 0xdeadbeef
     *   packed   = 0x00000000000000001234567890abcdef1234567890abcdef12345678deadbeef
     * Decoding reverses: selector = low 4 bytes; target = (key >> 32) & 0xffffffffffffffffffffffffffffffffffffffff
     */
    function _packFastPassKey(address target, bytes4 selector) internal pure returns (bytes32) {
        return bytes32((uint256(uint160(target)) << 32) | uint256(uint32(selector)));
    }

    /**
     * @notice Adds a new voter or updates an existing voter's power
     * @param _voter The address of the voter to add/update
     * @param _power The voting power to assign (must be > 0)
     */
    function _setVoter(address _voter, uint256 _power) private {
        if (_power == 0) revert ZeroPower();
        voters.set(_voter, _power);
    }

    /**
     * @notice Removes a voter from the governance system
     * @param _voter The address of the voter to remove
     */
    function _removeVoter(address _voter) private {
        if (!voters.contains(_voter)) revert NotVoter();
        voters.remove(_voter);
    }

    /**
     * @notice Extracts revert message from failed external call
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
