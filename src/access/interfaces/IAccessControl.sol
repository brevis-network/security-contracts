// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/**
 * @dev Interface for the AccessControl contract
 * Provides role-based access control functionality
 */
interface IAccessControl {
    // Events
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);
    event RoleAdminChanged(bytes32 indexed role, address indexed previousAdmin, address indexed newAdmin);

    // Errors
    error AccessControlUnauthorizedRole(address account, bytes32 role);
    error AccessControlAccountAlreadyHasRole(address account, bytes32 role);
    error AccessControlAccountDoesNotHaveRole(address account, bytes32 role);
    error AccessControlUnauthorizedAdmin(address account, bytes32 role);

    /**
     * @dev Checks if an account has a specific role
     * @param role The role to check
     * @param account The account to check
     * @return true if the account has the role, false otherwise
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the number of accounts that have a specific role
     * @param role The role to count members for
     * @return The number of accounts with the role
     */
    function roleMemberCount(bytes32 role) external view returns (uint256);

    /**
     * @dev Returns all accounts that have a specific role
     * @param role The role to get members for
     * @return accounts Array of addresses that have the role
     */
    function roleMembers(bytes32 role) external view returns (address[] memory accounts);

    /**
     * @dev Returns the admin address for a role (address(0) means owner-only admin)
     */
    function roleAdmin(bytes32 role) external view returns (address);

    /**
     * @dev Grants a role to an account
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Grants a role to multiple accounts
     * @param role The role to grant
     * @param accounts The accounts to grant the role to
     */
    function grantRoles(bytes32 role, address[] memory accounts) external;

    /**
     * @dev Revokes a role from an account
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes a role from multiple accounts
     * @param role The role to revoke
     * @param accounts The accounts to revoke the role from
     */
    function revokeRoles(bytes32 role, address[] memory accounts) external;

    /**
     * @dev Allows an account to renounce their own role
     * @param role The role to renounce
     */
    function renounceRole(bytes32 role) external;

    /**
     * @dev Sets the admin address for a role. Only callable by the owner.
     * @param role The role whose admin is being set
     * @param admin The new admin address (use address(0) to restrict to owner-only)
     */
    function setRoleAdmin(bytes32 role, address admin) external;
}
