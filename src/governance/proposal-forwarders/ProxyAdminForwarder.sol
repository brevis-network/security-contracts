// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../IGovernanceCouncil.sol";
import "./interfaces/IProxyAdmin.sol";
import "./ProposalForwarderBase.sol";

abstract contract ProxyAdminForwarder is ProposalForwarderBase {
    event ChangeAdminProposed(uint256 proposalId, address target);

    event UpgradeToProposed(uint256 proposalId, address target, address implementation);

    event UpgradeToAndCallProposed(uint256 proposalId, address target, address implementation, bytes data);

    event ChangeProxyAdminProposed(uint256 proposalId, address target, address proxy, address newAdmin);

    event UpgradeProposed(uint256 proposalId, address target, address proxy, address implementation);

    event UpgradeAndCallProposed(uint256 proposalId, address target, address proxy, address implementation, bytes data);

    function proposeChangeAdmin(address _target, address _newAdmin) external {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.changeAdmin.selector, _newAdmin);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit ChangeAdminProposed(proposalId, _target);
    }

    function proposeUpgradeTo(address _target, address _implementation) external {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgradeTo.selector, _implementation);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit UpgradeToProposed(proposalId, _target, _implementation);
    }

    function proposeUpgradeToAndCall(address _target, address _implementation, bytes calldata _data) external {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgradeToAndCall.selector, _implementation, _data);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit UpgradeToAndCallProposed(proposalId, _target, _implementation, _data);
    }

    function proposeChangeProxyAdmin(address _target, address _proxy, address _newAdmin) external {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.changeProxyAdmin.selector, _proxy, _newAdmin);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit ChangeProxyAdminProposed(proposalId, _target, _proxy, _newAdmin);
    }

    function proposeUpgrade(address _target, address _proxy, address _implementation) external {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgrade.selector, _proxy, _implementation);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit UpgradeProposed(proposalId, _target, _proxy, _implementation);
    }

    function proposeUpgradeAndCall(address _target, address _proxy, address _implementation, bytes calldata _data)
        external
    {
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgradeAndCall.selector, _proxy, _implementation, _data);
        uint256 proposalId = council.createProposal(msg.sender, _target, data);
        emit UpgradeAndCallProposed(proposalId, _target, _proxy, _implementation, _data);
    }
}
