// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title IProxyAdmin (owner-facing subset)
 * @notice Minimal interface for ProxyAdmin operations invoked by its owner.
 */
interface IProxyAdmin {
    function changeProxyAdmin(address _proxy, address _newAdmin) external;

    function upgrade(address _proxy, address _implementation) external;

    function upgradeAndCall(address _proxy, address _implementation, bytes calldata _data) external;
}
