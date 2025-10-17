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

    event CouncilInitialized(IGovernanceCouncil council);

    enum Action {
        Set,
        Add,
        Remove
    }

    constructor(address _council, address _initializer) {
        if (_council != address(0)) {
            council = IGovernanceCouncil(_council);
            emit CouncilInitialized(council);
            return; // Skip initializer if council is pre-set
        }
        initializer = _initializer;
    }

    function initCouncil(IGovernanceCouncil _council) public {
        if (msg.sender != initializer) revert OnlyInitializerCanInit();
        if (address(council) != address(0)) revert CouncilAddressAlreadySet();
        council = _council;
        emit CouncilInitialized(council);
    }
}
