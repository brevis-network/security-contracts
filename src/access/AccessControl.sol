// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Ownable.sol";
import "./interfaces/IAccessControl.sol";

/**
 * @title AccessControl (owner-superadmin + per-role admin)
 * @dev Role-based access control with enumerable members, built on top of {Ownable}.
 * Authorization model:
 *  - Owner is super-admin: can grant/revoke any role and set a role's admin.
 *  - Each role has an optional admin address via {roleAdmin}. If set (non-zero),
 *    that admin may grant/revoke that specific role. If unset (zero), only the owner
 *    can manage that role's members.
 *  - Members can always {renounceRole} for themselves.
 *  - Use {onlyRole} to guard functions by role membership.
 */
abstract contract AccessControl is Ownable, IAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Mapping from role id => set of member accounts
    mapping(bytes32 role => EnumerableSet.AddressSet) internal _roleMembers;

    // Mapping from role id => admin address (address(0) means owner-only)
    mapping(bytes32 role => address) private _roleAdmin;

    modifier onlyRole(bytes32 role) {
        if (!_roleMembers[role].contains(msg.sender)) {
            revert AccessControlUnauthorizedRole(msg.sender, role);
        }
        _;
    }

    modifier onlyRoleAdminOrOwner(bytes32 role) {
        if (owner() == msg.sender) {
            return;
        }
        address admin = _roleAdmin[role];
        if (admin != address(0) && admin == msg.sender) {
            return;
        }
        // If admin is zero, only owner may manage; otherwise, specific admin can manage.
        revert AccessControlUnauthorizedAdmin(msg.sender, role);
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
     * @dev Returns the admin for a role (address(0) means only owner can manage)
     */
    function roleAdmin(bytes32 role) public view returns (address) {
        return _roleAdmin[role];
    }

    /**
     * @dev Grants a role to an account. Callable by owner or the role's admin.
     */
    function grantRole(bytes32 role, address account) public onlyRoleAdminOrOwner(role) {
        _grantRole(role, account);
    }

    /**
     * @dev Grants a role to multiple accounts. Callable by owner or the role's admin.
     */
    function grantRoles(bytes32 role, address[] memory accounts) public onlyRoleAdminOrOwner(role) {
        for (uint256 i = 0; i < accounts.length; i++) {
            _grantRole(role, accounts[i]);
        }
    }

    /**
     * @dev Revokes a role from an account. Callable by owner or the role's admin.
     */
    function revokeRole(bytes32 role, address account) public onlyRoleAdminOrOwner(role) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes a role from multiple accounts. Callable by owner or the role's admin.
     */
    function revokeRoles(bytes32 role, address[] memory accounts) public onlyRoleAdminOrOwner(role) {
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

    /**
     * @dev Sets the admin for a role. Only callable by owner.
     * Using address(0) makes the role owner-managed only (no external admin).
     */
    function setRoleAdmin(bytes32 role, address admin) public onlyOwner {
        address previous = _roleAdmin[role];
        _roleAdmin[role] = admin;
        emit RoleAdminChanged(role, previous, admin);
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
