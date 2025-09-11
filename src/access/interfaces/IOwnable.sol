// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/**
 * @dev Interface for the Ownable contract
 * Provides basic ownership functionality
 */
interface IOwnable {
    // Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferCanceled(address indexed previousOwner, address indexed newOwner);

    // Errors
    error OwnerAlreadySet(address currentOwner);
    error OwnerZeroAddress();
    error OwnerUnauthorized(address caller, address owner);

    /**
     * @dev Returns the address of the current owner
     * @return The current owner's address
     */
    function owner() external view returns (address);

    /**
     * @dev Returns the address of the current pending owner
     * @return The current pending owner's address
     */
    function pendingOwner() external view returns (address);

    /**
     * @dev Transfers ownership of the contract to a new account
     * @param newOwner The address to transfer ownership to
     */
    function transferOwnership(address newOwner) external;

    /**
     * @dev Proposes a new owner for the contract
     * @param newOwner The address of the proposed new owner
     */
    function startOwnershipTransfer(address newOwner) external;

    /**
     * @dev Accepts the ownership transfer
     */
    function acceptOwnership() external;

    /**
     * @dev Cancels the ownership transfer
     */
    function cancelOwnershipTransfer() external;
}
