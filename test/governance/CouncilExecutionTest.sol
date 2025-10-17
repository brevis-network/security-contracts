// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./CouncilTest.sol";

contract CouncilExecutionTest is CouncilTest {
    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                  PROPOSAL EXECUTION TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testExecuteExternalProposal() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Get enough votes
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        // Check target state before execution
        assertEq(target.value(), 0);

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit IGovernanceCouncil.ExternalCallExecuted(address(target), MockTarget.setValue.selector);

        // Execute proposal
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);

        // Check target state after execution
        assertEq(target.value(), 42);
    }

    function testExecuteExternalProposalNotEnoughVotes() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Don't get enough additional votes (voter1 auto-voted, need more for 60% quorum)

        vm.expectRevert(IGovernanceCouncil.NotEnoughVotes.selector);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);
    }

    function testExecuteExternalProposalNonVoter() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanExecuteProposal.selector);
        vm.prank(nonVoter);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);
    }

    function testExecuteExternalProposalExpired() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Fast forward past deadline
        vm.warp(block.timestamp + ACTIVE_PERIOD + 1);

        vm.expectRevert(IGovernanceCouncil.DeadlinePassed.selector);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);
    }

    function testExecuteExternalProposalDataHashMismatch() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        bytes memory wrongData = abi.encodeWithSelector(MockTarget.setValue.selector, 99);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        vm.expectRevert(IGovernanceCouncil.DataHashMismatch.selector);
        vm.prank(voter1);
        council.executeProposal(
            proposalId,
            IGovernanceCouncil.ProposalType.External,
            address(target),
            wrongData // Wrong data
        );
    }

    function testExecuteExternalProposalRevertingCall() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.revertingFunction.selector);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        // External call now bubbles the exact revert data from target
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Mock revert"));
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);
    }

    function testExecuteExternalProposalAutoVoteAtExecution() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Don't vote separately, execution should auto-vote
        assertFalse(council.getVote(proposalId, voter2));

        vm.prank(voter2);
        council.voteProposal(proposalId, false); // Vote no initially
        assertFalse(council.getVote(proposalId, voter2));

        // Execute - should auto-vote yes for executor
        vm.prank(voter2);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);

        // Executor should now have yes vote
        assertTrue(council.getVote(proposalId, voter2));
        assertEq(target.value(), 42);
    }

    function testExecuteExternalProposalReentrancyProtection() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        // Execute first time
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);

        // Try to execute again - should fail because deadline was set to 0
        vm.expectRevert(IGovernanceCouncil.DeadlinePassed.selector);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.External, address(target), data);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                PARAMETER UPDATE TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testCreateAndExecuteParamUpdate() public {
        uint256 newActivePeriod = 10000;
        uint256 oldActivePeriod = council.params(IGovernanceCouncil.Param.ActivePeriod);

        vm.prank(voter1);
        uint256 proposalId = council.proposeParamUpdate(IGovernanceCouncil.Param.ActivePeriod, newActivePeriod);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        bytes memory data = abi.encode(IGovernanceCouncil.Param.ActivePeriod, newActivePeriod);

        // Expect ParamUpdated event
        vm.expectEmit(true, false, false, true);
        emit IGovernanceCouncil.ParamUpdated(IGovernanceCouncil.Param.ActivePeriod, oldActivePeriod, newActivePeriod);

        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.ParamUpdate, address(0), data);

        assertEq(council.params(IGovernanceCouncil.Param.ActivePeriod), newActivePeriod);
    }

    function testExecuteParamUpdateInvalidActivePeriod() public {
        uint256 invalidPeriod = 1000; // Too short

        vm.prank(voter1);
        uint256 proposalId = council.proposeParamUpdate(IGovernanceCouncil.Param.ActivePeriod, invalidPeriod);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        bytes memory data = abi.encode(IGovernanceCouncil.Param.ActivePeriod, invalidPeriod);

        vm.expectRevert(IGovernanceCouncil.InvalidActivePeriod.selector);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.ParamUpdate, address(0), data);
    }

    function testExecuteParamUpdateInvalidThreshold() public {
        uint256 invalidThreshold = 150; // > 100

        vm.prank(voter1);
        uint256 proposalId = council.proposeParamUpdate(IGovernanceCouncil.Param.QuorumThreshold, invalidThreshold);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        bytes memory data = abi.encode(IGovernanceCouncil.Param.QuorumThreshold, invalidThreshold);

        vm.expectRevert(IGovernanceCouncil.InvalidThreshold.selector);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.ParamUpdate, address(0), data);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                    VOTER UPDATE TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testCreateAndExecuteVoterUpdate() public {
        address newVoter = makeAddr("newVoter");
        address[] memory voters = new address[](2);
        uint256[] memory powers = new uint256[](2);

        voters[0] = newVoter;
        voters[1] = voter3; // Remove voter3 by setting power to 0
        powers[0] = 200;
        powers[1] = 0;

        vm.prank(voter1);
        uint256 proposalId = council.proposeVoterUpdate(voters, powers);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        bytes memory data = abi.encode(voters, powers);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.VoterUpdate, address(0), data);

        // Check new voter added
        assertEq(council.getVoterPower(newVoter), 200);

        // Check voter3 removed
        assertEq(council.getVoterPower(voter3), 0);

        // Check total voters count
        (address[] memory allVoters,,) = council.getVoters();
        assertEq(allVoters.length, 3); // voter1, voter2, newVoter
    }

    function testExecuteVoterUpdateNoVotersRemaining() public {
        // Try to remove all voters
        address[] memory voters = new address[](3);
        uint256[] memory powers = new uint256[](3);

        voters[0] = voter1;
        voters[1] = voter2;
        voters[2] = voter3;
        powers[0] = 0;
        powers[1] = 0;
        powers[2] = 0;

        vm.prank(voter1);
        uint256 proposalId = council.proposeVoterUpdate(voters, powers);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        bytes memory data = abi.encode(voters, powers);

        vm.expectRevert(IGovernanceCouncil.NoVotersRemaining.selector);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.VoterUpdate, address(0), data);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                   FORWARDER UPDATE TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testCreateAndExecuteProposalForwarderUpdate() public {
        address newForwarder = makeAddr("newForwarder");
        address[] memory forwarders = new address[](2);
        bool[] memory authorized = new bool[](2);

        forwarders[0] = newForwarder;
        forwarders[1] = forwarder1; // Remove existing forwarder
        authorized[0] = true;
        authorized[1] = false;

        vm.prank(voter1);
        uint256 proposalId = council.proposeProposalForwarderUpdate(forwarders, authorized);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        bytes memory data = abi.encode(forwarders, authorized);

        // Expect ProposalForwarderUpdated events
        vm.expectEmit(true, false, false, true);
        emit IGovernanceCouncil.ProposalForwarderUpdated(newForwarder, true);
        vm.expectEmit(true, false, false, true);
        emit IGovernanceCouncil.ProposalForwarderUpdated(forwarder1, false);

        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.ProposalForwarderUpdate, address(0), data);

        // Check new forwarder added
        assertTrue(council.isProposalForwarder(newForwarder));

        // Check old forwarder removed
        assertFalse(council.isProposalForwarder(forwarder1));

        // Check forwarders array
        address[] memory allForwarders = council.getProposalForwarders();
        assertEq(allForwarders.length, 1);
        assertEq(allForwarders[0], newForwarder);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                   TOKEN TRANSFER TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testCreateAndExecuteTokenTransfer() public {
        address receiver = makeAddr("receiver");
        uint256 amount = 100 * 10 ** token.decimals();

        vm.prank(voter1);
        uint256 proposalId = council.proposeTokenTransfer(receiver, address(token), amount);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        uint256 receiverBalanceBefore = token.balanceOf(receiver);
        uint256 councilBalanceBefore = token.balanceOf(address(council));

        bytes memory data = abi.encode(receiver, address(token), amount);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.TokenTransfer, address(0), data);

        assertEq(token.balanceOf(receiver), receiverBalanceBefore + amount);
        assertEq(token.balanceOf(address(council)), councilBalanceBefore - amount);
    }

    function testCreateAndExecuteNativeTokenTransfer() public {
        address payable receiver = payable(makeAddr("receiver"));
        uint256 amount = 1 ether;

        vm.prank(voter1);
        uint256 proposalId = council.proposeTokenTransfer(receiver, address(0), amount);

        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        uint256 receiverBalanceBefore = receiver.balance;
        uint256 councilBalanceBefore = address(council).balance;

        bytes memory data = abi.encode(receiver, address(0), amount);
        vm.prank(voter1);
        council.executeProposal(proposalId, IGovernanceCouncil.ProposalType.TokenTransfer, address(0), data);

        assertEq(receiver.balance, receiverBalanceBefore + amount);
        assertEq(address(council).balance, councilBalanceBefore - amount);
    }

    function testNativeTokenTransferGasLimit() public {
        uint256 newGasLimit = 100000;

        vm.prank(voter1);
        council.setNativeTokenTransferGas(newGasLimit);

        assertEq(council.nativeTokenTransferGas(), newGasLimit);
    }

    function testNativeTokenTransferGasLimitNonVoter() public {
        vm.expectRevert(IGovernanceCouncil.InvalidCaller.selector);
        vm.prank(nonVoter);
        council.setNativeTokenTransferGas(100000);
    }

    function testReceiveNativeToken() public {
        uint256 balanceBefore = address(council).balance;
        uint256 amount = 5 ether;

        vm.deal(voter1, amount);
        vm.prank(voter1);
        (bool success,) = address(council).call{value: amount}("");

        assertTrue(success);
        assertEq(address(council).balance, balanceBefore + amount);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                    VIEW FUNCTION TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testGetVoters() public view {
        (address[] memory addrs, uint256[] memory powers,) = council.getVoters();

        assertEq(addrs.length, 3);
        assertEq(powers.length, 3);

        // Note: Order may vary due to EnumerableMap
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;

        for (uint256 i = 0; i < addrs.length; i++) {
            if (addrs[i] == voter1 && powers[i] == VOTER1_POWER) found1 = true;
            if (addrs[i] == voter2 && powers[i] == VOTER2_POWER) found2 = true;
            if (addrs[i] == voter3 && powers[i] == VOTER3_POWER) found3 = true;
        }

        assertTrue(found1);
        assertTrue(found2);
        assertTrue(found3);
    }

    function testGetVoterPower() public view {
        assertEq(council.getVoterPower(voter1), VOTER1_POWER);
        assertEq(council.getVoterPower(voter2), VOTER2_POWER);
        assertEq(council.getVoterPower(voter3), VOTER3_POWER);
        assertEq(council.getVoterPower(nonVoter), 0);
    }

    function testConstants() public view {
        assertEq(council.THRESHOLD_DECIMAL(), 100);
        assertEq(council.MIN_ACTIVE_PERIOD(), 3600);
        assertEq(council.MAX_ACTIVE_PERIOD(), 2419200);
    }
}
