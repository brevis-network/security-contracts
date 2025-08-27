// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../../access/interfaces/IOwnable.sol";
import "../../access/interfaces/IAccessControl.sol";
import "../IGovernanceCouncil.sol";
import "./ProposalForwarderBase.sol";

abstract contract AccessControlForwarder is ProposalForwarderBase {
    event TransferOwnershipProposed(uint256 proposalId, address target, address newOwner);

    event GrantRoleProposed(uint256 proposalId, address target, bytes32 role, address account);

    event GrantRolesProposed(uint256 proposalId, address target, bytes32 role, address[] accounts);

    event RevokeRoleProposed(uint256 proposalId, address target, bytes32 role, address account);

    event RevokeRolesProposed(uint256 proposalId, address target, bytes32 role, address[] accounts);

    function proposeTransferOwnership(address _target, address _newOwner) external {
        bytes memory data = abi.encodeWithSelector(IOwnable.transferOwnership.selector, _newOwner);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit TransferOwnershipProposed(proposalId, _target, _newOwner);
    }

    function proposeGrantRole(address _target, bytes32 _role, address _account) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.grantRole.selector, _role, _account);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit GrantRoleProposed(proposalId, _target, _role, _account);
    }

    function proposeGrantRoles(address _target, bytes32 _role, address[] calldata _accounts) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.grantRoles.selector, _role, _accounts);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit GrantRolesProposed(proposalId, _target, _role, _accounts);
    }

    function proposeRevokeRole(address _target, bytes32 _role, address _account) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.revokeRole.selector, _role, _account);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit RevokeRoleProposed(proposalId, _target, _role, _account);
    }

    function proposeRevokeRoles(address _target, bytes32 _role, address[] calldata _accounts) external {
        bytes memory data = abi.encodeWithSelector(IAccessControl.revokeRoles.selector, _role, _accounts);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit RevokeRolesProposed(proposalId, _target, _role, _accounts);
    }
}
