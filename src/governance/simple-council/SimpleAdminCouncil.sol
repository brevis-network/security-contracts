// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./SimpleCouncil.sol";
import "../../access/interfaces/IOwnable.sol";
import "../../access/interfaces/IAccessControl.sol";
import "../proposal-forwarders/interfaces/IProxyAdmin.sol";

/**
 * @title SimpleAdminCouncil
 * @author Brevis Network
 * @notice Minimal council extension that adds proposal helpers for admin operations
 * @dev Extends SimpleCouncil and provides convenience `propose*` functions that
 *      encode IOwnable and IAccessControl calls (transfer ownership, start/cancel/accept
 *      ownership transfer, grant/revoke roles, set role admin). Proposals are created
 *      via `createProposal` and executed through `executeProposal` on SimpleCouncil.
 */
contract SimpleAdminCouncil is SimpleCouncil {
    // Initializes the council with the provided voter addresses, required yes votes, and proposal active period
    constructor(address[] memory _voters, uint256 _requiredYesVotes, uint256 _activePeriod)
        SimpleCouncil(_voters, _requiredYesVotes, _activePeriod)
    {}

    // Ownable and AccessControl operations
    event TransferOwnershipProposed(uint256 proposalId, address target, address newOwner);
    event StartOwnershipTransferProposed(uint256 proposalId, address target, address newOwner);
    event AcceptOwnershipProposed(uint256 proposalId, address target);
    event CancelOwnershipTransferProposed(uint256 proposalId, address target);
    event GrantRoleProposed(uint256 proposalId, address target, bytes32 role, address account);
    event GrantRolesProposed(uint256 proposalId, address target, bytes32 role, address[] accounts);
    event RevokeRoleProposed(uint256 proposalId, address target, bytes32 role, address account);
    event RevokeRolesProposed(uint256 proposalId, address target, bytes32 role, address[] accounts);
    event SetRoleAdminProposed(uint256 proposalId, address target, bytes32 role, address admin);

    // ProxyAdmin owner-facing operations (assumes `target` is a ProxyAdmin owned by this council)
    event ChangeProxyAdminProposed(uint256 proposalId, address target, address proxy, address newAdmin);
    event UpgradeProposed(uint256 proposalId, address target, address proxy, address implementation);
    event UpgradeAndCallProposed(uint256 proposalId, address target, address proxy, address implementation, bytes data);

    // ERC20 operations
    event ERC20TransferProposed(uint256 proposalId, address token, address to, uint256 amount);

    // =========================== Ownable and AccessControl helpers ===========================
    function proposeTransferOwnership(address _target, address _newOwner) external {
        bytes memory data = abi.encodeWithSelector(IOwnable.transferOwnership.selector, _newOwner);
        uint256 proposalId = createProposal(_target, data);
        emit TransferOwnershipProposed(proposalId, _target, _newOwner);
    }

    function proposeStartOwnershipTransfer(address _target, address _newOwner) external {
        bytes memory data = abi.encodeWithSelector(IOwnable.startOwnershipTransfer.selector, _newOwner);
        uint256 proposalId = createProposal(_target, data);
        emit StartOwnershipTransferProposed(proposalId, _target, _newOwner);
    }

    function proposeAcceptOwnership(address _target) external {
        bytes memory data = abi.encodeWithSelector(IOwnable.acceptOwnership.selector);
        uint256 proposalId = createProposal(_target, data);
        emit AcceptOwnershipProposed(proposalId, _target);
    }

    function proposeCancelOwnershipTransfer(address _target) external {
        bytes memory data = abi.encodeWithSelector(IOwnable.cancelOwnershipTransfer.selector);
        uint256 proposalId = createProposal(_target, data);
        emit CancelOwnershipTransferProposed(proposalId, _target);
    }

    function proposeGrantRole(address _target, bytes32 _role, address _account) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.grantRole.selector, _role, _account);
        uint256 proposalId = createProposal(_target, data);
        emit GrantRoleProposed(proposalId, _target, _role, _account);
    }

    function proposeGrantRoles(address _target, bytes32 _role, address[] calldata _accounts) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.grantRoles.selector, _role, _accounts);
        uint256 proposalId = createProposal(_target, data);
        emit GrantRolesProposed(proposalId, _target, _role, _accounts);
    }

    function proposeRevokeRole(address _target, bytes32 _role, address _account) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.revokeRole.selector, _role, _account);
        uint256 proposalId = createProposal(_target, data);
        emit RevokeRoleProposed(proposalId, _target, _role, _account);
    }

    function proposeRevokeRoles(address _target, bytes32 _role, address[] calldata _accounts) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.revokeRoles.selector, _role, _accounts);
        uint256 proposalId = createProposal(_target, data);
        emit RevokeRolesProposed(proposalId, _target, _role, _accounts);
    }

    function proposeSetRoleAdmin(address _target, bytes32 _role, address _admin) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.setRoleAdmin.selector, _role, _admin);
        uint256 proposalId = createProposal(_target, data);
        emit SetRoleAdminProposed(proposalId, _target, _role, _admin);
    }

    // =========================== ProxyAdmin owner helpers ===========================
    function proposeChangeProxyAdmin(address _proxyAdmin, address _proxy, address _newAdmin) external {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.changeProxyAdmin.selector, _proxy, _newAdmin);
        uint256 proposalId = createProposal(_proxyAdmin, data);
        emit ChangeProxyAdminProposed(proposalId, _proxyAdmin, _proxy, _newAdmin);
    }

    function proposeUpgrade(address _proxyAdmin, address _proxy, address _implementation) external {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgrade.selector, _proxy, _implementation);
        uint256 proposalId = createProposal(_proxyAdmin, data);
        emit UpgradeProposed(proposalId, _proxyAdmin, _proxy, _implementation);
    }

    function proposeUpgradeAndCall(address _proxyAdmin, address _proxy, address _implementation, bytes calldata _data)
        external
    {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgradeAndCall.selector, _proxy, _implementation, _data);
        uint256 proposalId = createProposal(_proxyAdmin, data);
        emit UpgradeAndCallProposed(proposalId, _proxyAdmin, _proxy, _implementation, _data);
    }

    // =========================== ERC20 helpers ===========================
    function proposeERC20Transfer(address _token, address _to, uint256 _amount) external {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount);
        uint256 proposalId = createProposal(_token, data);
        emit ERC20TransferProposed(proposalId, _token, _to, _amount);
    }
}
