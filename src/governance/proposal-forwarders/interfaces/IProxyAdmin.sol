// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IProxyAdmin {
    function changeAdmin(address _newAdmin) external;

    function upgradeTo(address _implementation) external;

    function upgradeToAndCall(address _implementation, bytes memory _data) external;

    function changeProxyAdmin(address _proxy, address _newAdmin) external;

    function upgrade(address _proxy, address _implementation) external;

    function upgradeAndCall(address _proxy, address _implementation, bytes calldata _data) external;
}
