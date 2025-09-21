// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./interfaces/IOwnable.sol";

/**
 * @title Ownable (direct + two-step ownership transfers)
 * @notice Basic access control: an owner can call functions guarded by {onlyOwner}.
 * @dev This contract supports two ways to change ownership:
 *  - Direct transfer via {transferOwnership}: immediate change of owner.
 *  - Two-step transfer via {startOwnershipTransfer} -> {acceptOwnership}: adds an
 *    explicit handoff that must be accepted by the pending owner.
 *
 * Initialization and constraints:
 *  - The constructor sets the deployer as the initial owner.
 *  - For proxy patterns, use {initOwner} or {initOwner(address)} exactly once;
 *    calling these when an owner is already set reverts with {OwnerAlreadySet}.
 *  - This implementation intentionally does NOT support renounceOwnership.
 *    Rationale: the proxy initializer(s) rely on the invariant that after
 *    initialization, {_owner} is never the zero address. Allowing renounce
 *    would reset {_owner} to address(0), re-enabling {initOwner} and creating
 *    a critical re-initialization/takeover risk in upgradeable deployments.
 */
abstract contract Ownable is IOwnable {
    address private _owner;
    address private _pendingOwner;

    /**
     * @notice Sets the deployer as the initial owner.
     * @dev Called at deployment time (non-proxy). For proxies, see {initOwner}.
     */
    constructor() {
        _setOwner(msg.sender);
    }

    /**
     * @dev Restricts a function to the current owner; otherwise reverts.
     */
    modifier onlyOwner() {
        if (owner() != msg.sender) {
            revert OwnerUnauthorized(msg.sender, owner());
        }
        _;
    }

    /**
     * @notice One-time initializer for proxy deployments to set the owner to the caller.
     * @dev Reverts if the owner is already initialized.
     */
    function initOwner() internal {
        if (_owner != address(0)) {
            revert OwnerAlreadySet(_owner);
        }
        _setOwner(msg.sender);
    }

    /**
     * @notice One-time initializer for proxy deployments to set the owner to a specific address.
     * @dev Reverts if already initialized or if `newOwner` is the zero address.
     * @param newOwner The address to set as the initial owner.
     */
    function initOwner(address newOwner) internal {
        if (_owner != address(0)) {
            revert OwnerAlreadySet(_owner);
        }
        if (newOwner == address(0)) {
            revert OwnerZeroAddress();
        }
        _setOwner(newOwner);
    }

    /**
     * @notice Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @notice Returns the address currently proposed to become the new owner, if any.
     * @dev Returns address(0) when no two-step transfer is in progress.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @notice Transfers ownership immediately to `newOwner`.
     * @dev Can only be called by the current owner.
     * Clears any pending proposal via {_setOwner}.
     * @param newOwner The address to receive ownership immediately.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnerZeroAddress();
        }
        _setOwner(newOwner);
    }

    /**
     * @notice Propose `newOwner` as the pending owner for a two-step transfer.
     * @dev Can only be called by the current owner.
     * @param newOwner The address proposed to accept and become the new owner.
     */
    function startOwnershipTransfer(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnerZeroAddress();
        }
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /**
     * @notice Called by the pending owner to accept ownership.
     * @dev Can only be called by the _pendingOwner.
     */
    function acceptOwnership() public virtual {
        if (msg.sender != _pendingOwner) {
            revert OwnerUnauthorized(msg.sender, _pendingOwner);
        }
        _setOwner(_pendingOwner);
    }

    /**
     * @notice Cancels the in-progress two-step ownership transfer.
     * @dev Does not change the current owner. Can only be called by the current owner.
     */
    function cancelOwnershipTransfer() public virtual onlyOwner {
        address oldPendingOwner = _pendingOwner;
        delete _pendingOwner;
        emit OwnershipTransferCanceled(_owner, oldPendingOwner);
    }

    /**
     * @dev Internal owner setter. Always clears {_pendingOwner} to prevent stale accepts.
     * @param newOwner The address to set as the new owner.
     */
    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        // Clearing any pending owner guarantees that once ownership changes,
        // there is no stale pending owner that can later claim ownership.
        if (_pendingOwner != address(0)) {
            delete _pendingOwner;
        }
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
