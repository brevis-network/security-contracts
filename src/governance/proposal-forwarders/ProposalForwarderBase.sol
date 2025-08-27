// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../IGovernanceCouncil.sol";

abstract contract ProposalForwarderBase {
    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                             ERRORS
    // ════════════════════════════════════════════════════════════════════════════════════════

    error OnlyInitializerCanInit();
    error CouncilAddressAlreadySet();

    IGovernanceCouncil public council;
    address private initializer;

    enum Action {
        Set,
        Add,
        Remove
    }

    constructor(address _initializer) {
        initializer = _initializer;
    }

    function initCouncil(IGovernanceCouncil _council) public {
        if (msg.sender != initializer) revert OnlyInitializerCanInit();
        if (address(council) != address(0)) revert CouncilAddressAlreadySet();
        council = _council;
    }
}
