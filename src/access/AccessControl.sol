// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Ownable.sol";
import "./interfaces/IAccessControl.sol";

/**
 * @dev Abstract contract that provides role-based access control functionality
 * Extends Ownable to allow the owner to manage roles and permissions
 */
abstract contract AccessControl is Ownable, IAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Mapping from role id => set of member accounts
    mapping(bytes32 role => EnumerableSet.AddressSet) internal _roleMembers;

    modifier onlyRole(bytes32 role) {
        if (!_roleMembers[role].contains(msg.sender)) {
            revert AccessControlUnauthorizedRole(msg.sender, role);
        }
        _;
    }

    /**
     * @dev Checks if an account has a specific role
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roleMembers[role].contains(account);
    }

    /**
     * @dev Returns the number of accounts that have a specific role
     */
    function roleMemberCount(bytes32 role) public view returns (uint256) {
        return _roleMembers[role].length();
    }

    /**
     * @dev Returns all accounts that have a specific role
     */
    function roleMembers(bytes32 role) public view returns (address[] memory accounts) {
        return _roleMembers[role].values();
    }

    /**
     * @dev Grants a role to an account. Only callable by owner
     */
    function grantRole(bytes32 role, address account) public onlyOwner {
        _grantRole(role, account);
    }

    /**
     * @dev Grants a role to multiple accounts. Only callable by owner
     */
    function grantRoles(bytes32 role, address[] memory accounts) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _grantRole(role, accounts[i]);
        }
    }

    /**
     * @dev Revokes a role from an account. Only callable by owner
     */
    function revokeRole(bytes32 role, address account) public onlyOwner {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes a role from multiple accounts. Only callable by owner
     */
    function revokeRoles(bytes32 role, address[] memory accounts) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _revokeRole(role, accounts[i]);
        }
    }

    /**
     * @dev Allows an account to renounce their own role
     */
    function renounceRole(bytes32 role) public {
        _revokeRole(role, msg.sender);
    }

    // -------------- internal functions --------------

    function _grantRole(bytes32 role, address account) internal {
        if (_roleMembers[role].contains(account)) {
            revert AccessControlAccountAlreadyHasRole(account, role);
        }
        _roleMembers[role].add(account);
        emit RoleGranted(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (!_roleMembers[role].contains(account)) {
            revert AccessControlAccountDoesNotHaveRole(account, role);
        }
        _roleMembers[role].remove(account);
        emit RoleRevoked(role, account);
    }
}
