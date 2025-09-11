// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "./AccessControl.sol";
import "./interfaces/IPauserControl.sol";

/**
 * @dev Abstract contract that adds pause/unpause functionality with role-based access control
 * Only accounts with PAUSER_ROLE can pause or unpause the contract
 */
abstract contract PauserControl is AccessControl, Pausable, IPauserControl {
    // 65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    modifier onlyPauser() {
        if (!hasRole(PAUSER_ROLE, msg.sender)) {
            revert PauserUnauthorized(msg.sender);
        }
        _;
    }

    function pause() public virtual override onlyPauser {
        _pause();
    }

    function unpause() public virtual override onlyPauser {
        _unpause();
    }

    function paused() public view override(Pausable, IPauserControl) returns (bool) {
        return Pausable.paused();
    }
}
