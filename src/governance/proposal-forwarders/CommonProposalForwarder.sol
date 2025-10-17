// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./ProposalForwarderBase.sol";
import "./AccessControlForwarder.sol";
import "./ProxyAdminForwarder.sol";

contract CommonProposalForwarder is ProposalForwarderBase, AccessControlForwarder, ProxyAdminForwarder {
    constructor(address _council, address _initializer) ProposalForwarderBase(_council, _initializer) {}
}
