// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./forwarders/ProposalForwarderBase.sol";
import "./forwarders/AccessControlForwarder.sol";
import "./forwarders/ProxyAdminForwarder.sol";

contract AdminProposalForwarder is ProposalForwarderBase, AccessControlForwarder, ProxyAdminForwarder {
    constructor(address _council, address _initializer) ProposalForwarderBase(_council, _initializer) {}
}
