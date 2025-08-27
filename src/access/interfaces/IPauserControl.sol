// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.18;

/**
 * @dev Interface for the PauserControl contract
 * Provides pause/unpause functionality with role-based access control
 */
interface IPauserControl {
    // Errors
    error PauserUnauthorized(address caller);

    /**
     * @dev Returns the PAUSER_ROLE constant
     * @return The bytes32 value of the PAUSER_ROLE
     */
    function PAUSER_ROLE() external pure returns (bytes32);

    /**
     * @dev Pauses the contract. Only callable by accounts with PAUSER_ROLE
     */
    function pause() external;

    /**
     * @dev Unpauses the contract. Only callable by accounts with PAUSER_ROLE
     */
    function unpause() external;

    /**
     * @dev Returns true if the contract is paused, and false otherwise
     * @return true if paused, false if not paused
     */
    function paused() external view returns (bool);
}
