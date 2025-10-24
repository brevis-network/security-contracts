// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./CouncilTest.sol";

contract CouncilFastPassTest is CouncilTest {
    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                FAST-PASS AUTHORIZATION TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testCreateFastPassUpdateProposal() public {
        address[] memory targets = new address[](2);
        bytes4[] memory selectors = new bytes4[](2);
        bool[] memory authorized = new bool[](2);

        targets[0] = address(target);
        targets[1] = address(token);
        selectors[0] = MockTarget.setValue.selector;
        selectors[1] = bytes4(0); // wildcard
        authorized[0] = true;
        authorized[1] = true;

        vm.prank(voter1);
        uint256 proposalId = council.proposeFastPassUpdate(targets, selectors, authorized);

        assertEq(proposalId, 0);
        assertTrue(council.getVote(proposalId, voter1));
    }

    function testCreateFastPassUpdateProposalInvalidLength() public {
        address[] memory targets = new address[](2);
        bytes4[] memory selectors = new bytes4[](1); // Mismatched
        bool[] memory authorized = new bool[](2);

        vm.expectRevert(IGovernanceCouncil.InvalidLength.selector);
        vm.prank(voter1);
        council.proposeFastPassUpdate(targets, selectors, authorized);
    }

    function testExecuteFastPassUpdate() public {
        // Create and execute fast-pass authorization proposal
        vm.prank(voter1);
        uint256 proposalId = council.proposeFastPassUpdate(
            _addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true)
        );

        _executeProposal(
            proposalId,
            address(council),
            abi.encodeCall(
                council.updateFastPass,
                (_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
            )
        );

        // Check authorization was added
        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setValue.selector));

        bytes32[] memory authKeys = council.getFastPassAuthorizations();
        assertEq(authKeys.length, 1);
    }

    function testExecuteFastPassUpdateRemoveAuthorization() public {
        // First add authorization
        vm.prank(voter1);
        uint256 proposalId1 = council.proposeFastPassUpdate(
            _addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true)
        );

        _executeProposal(
            proposalId1,
            address(council),
            abi.encodeCall(
                council.updateFastPass,
                (_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
            )
        );

        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setValue.selector));

        // Then remove authorization
        vm.prank(voter1);
        uint256 proposalId2 = council.proposeFastPassUpdate(
            _addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(false)
        );

        _executeProposal(
            proposalId2,
            address(council),
            abi.encodeCall(
                council.updateFastPass,
                (_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(false))
            )
        );

        assertFalse(council.isFastPassAuthorized(address(target), MockTarget.setValue.selector));
        assertEq(council.getFastPassAuthorizations().length, 0);
    }

    function testFastPassWildcardAuthorization() public {
        // Authorize all functions on target with wildcard
        vm.prank(voter1);
        uint256 proposalId =
            council.proposeFastPassUpdate(_addressArray(address(target)), _bytes4Array(bytes4(0)), _boolArray(true));

        _executeProposal(
            proposalId,
            address(council),
            abi.encodeCall(
                council.updateFastPass, (_addressArray(address(target)), _bytes4Array(bytes4(0)), _boolArray(true))
            )
        );

        // Check different functions are authorized
        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setValue.selector));
        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setFlag.selector));
        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setOwner.selector));
        assertTrue(council.isFastPassAuthorized(address(target), bytes4(0x12345678))); // Random selector
    }

    function testFastPassSpecificOverridesWildcard() public {
        // Add wildcard authorization
        vm.prank(voter1);
        uint256 proposalId1 =
            council.proposeFastPassUpdate(_addressArray(address(target)), _bytes4Array(bytes4(0)), _boolArray(true));

        _executeProposal(
            proposalId1,
            address(council),
            abi.encodeCall(
                council.updateFastPass, (_addressArray(address(target)), _bytes4Array(bytes4(0)), _boolArray(true))
            )
        );

        // Add specific authorization for same function
        vm.prank(voter1);
        uint256 proposalId2 = council.proposeFastPassUpdate(
            _addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true)
        );

        _executeProposal(
            proposalId2,
            address(council),
            abi.encodeCall(
                council.updateFastPass,
                (_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
            )
        );

        // Both should be authorized
        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setValue.selector));
        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setFlag.selector)); // From wildcard

        // Should have 2 authorizations now
        assertEq(council.getFastPassAuthorizations().length, 2);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                FAST-PASS THRESHOLD TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testFastPassThresholdDetection() public {
        // First authorize fast-pass for setValue
        vm.prank(voter1);
        uint256 fastPassProposalId = council.proposeFastPassUpdate(
            _addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true)
        );

        _executeProposal(
            fastPassProposalId,
            address(council),
            abi.encodeCall(
                council.updateFastPass,
                (_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
            )
        );

        // Create external proposal for setValue (should use fast-pass threshold)
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter2);
        uint256 proposalId = council.createProposal(address(target), data);

        // Should use fast-pass threshold (40%)
        (uint256 totalPower, uint256 yesVotes, bool pass) =
            council.countVotes(proposalId, address(target), MockTarget.setValue.selector);

        assertEq(totalPower, TOTAL_POWER);
        assertEq(yesVotes, VOTER2_POWER); // Only voter2 voted (auto-vote)
        assertFalse(pass); // 50/175 = 28% < 40% fast-pass threshold

        // Add voter1's vote to reach fast-pass threshold
        vm.prank(voter1);
        council.voteProposal(proposalId, true);

        (totalPower, yesVotes, pass) = council.countVotes(proposalId, address(target), MockTarget.setValue.selector);

        assertEq(yesVotes, VOTER1_POWER + VOTER2_POWER);
        assertTrue(pass); // 150/175 = 85% > 40% fast-pass threshold
    }

    function testQuorumThresholdWhenNoFastPass() public {
        // Create external proposal for setValue (no fast-pass authorization)
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Should use quorum threshold (60%)
        (uint256 totalPower, uint256 yesVotes, bool pass) =
            council.countVotes(proposalId, address(target), MockTarget.setValue.selector);

        assertEq(yesVotes, VOTER1_POWER);
        assertFalse(pass); // 100/175 = 57% < 60% quorum threshold

        // Add voter2's vote to reach quorum threshold
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        (totalPower, yesVotes, pass) = council.countVotes(proposalId, address(target), MockTarget.setValue.selector);

        assertEq(yesVotes, VOTER1_POWER + VOTER2_POWER);
        assertTrue(pass); // 150/175 = 85% > 60% quorum threshold
    }

    function testNonExternalProposalsUseQuorumThreshold() public {
        // Parameter update should always use quorum threshold
        vm.prank(voter1);
        uint256 proposalId = council.proposeParamUpdate(IGovernanceCouncil.Param.ActivePeriod, 10000);

        (, uint256 yesVotes, bool pass) =
            council.countVotes(proposalId, address(council), GovernanceCouncil.updateParam.selector);

        assertEq(yesVotes, VOTER1_POWER);
        assertFalse(pass); // Should use 60% quorum threshold, not 40% fast-pass
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                    HELPER FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function _executeProposal(uint256 proposalId, address target, bytes memory data) internal {
        // Get enough votes to pass
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        vm.prank(voter1);
        council.executeProposal(proposalId, target, data);
    }

    function _addressArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    function _bytes4Array(bytes4 selector) internal pure returns (bytes4[] memory) {
        bytes4[] memory arr = new bytes4[](1);
        arr[0] = selector;
        return arr;
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                             DYNAMIC FAST-PASS BEHAVIOR TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testDynamicFastPassAfterProposalCreation() public {
        // Create external proposal without fast-pass authorization
        bytes memory callData = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), callData);

        // Verify it initially requires quorum threshold (3 voters needed)
        (,, bool passesBeforeFastPass) = council.countVotes(proposalId, address(target), MockTarget.setValue.selector);
        assertFalse(passesBeforeFastPass); // Only voter1 voted (auto-vote), need 3 total

        // Add fast-pass authorization for this function
        address[] memory targets = _addressArray(address(target));
        bytes4[] memory selectors = _bytes4Array(MockTarget.setValue.selector);
        bool[] memory authorized = _boolArray(true);

        vm.prank(voter1);
        uint256 fastPassProposalId = council.proposeFastPassUpdate(targets, selectors, authorized);

        // Execute fast-pass authorization (voter1 + voter2 = enough for fast-pass update)
        vm.prank(voter2);
        council.voteProposal(fastPassProposalId, true);

        vm.prank(voter2);
        council.executeProposal(
            fastPassProposalId,
            address(council),
            abi.encodeCall(council.updateFastPass, (targets, selectors, authorized))
        );

        // Now the original proposal should pass with fast-pass threshold (2 voters needed)
        (,, bool passesAfterFastPass) = council.countVotes(proposalId, address(target), MockTarget.setValue.selector);
        assertTrue(passesAfterFastPass); // voter1's auto-vote (100 power) is enough for fast-pass threshold (40% = 70 power)

        // Add voter2's vote - now should pass with fast-pass threshold
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        (,, bool passesWithTwoVotes) = council.countVotes(proposalId, address(target), MockTarget.setValue.selector);
        assertTrue(passesWithTwoVotes); // 2 votes now sufficient due to fast-pass
    }

    function testDynamicFastPassRevocationIncreasesThreshold() public {
        // First add fast-pass authorization
        address[] memory targets = _addressArray(address(target));
        bytes4[] memory selectors = _bytes4Array(MockTarget.setValue.selector);
        bool[] memory authorized = _boolArray(true);

        vm.prank(voter1);
        uint256 authProposalId = council.proposeFastPassUpdate(targets, selectors, authorized);

        vm.prank(voter2);
        council.voteProposal(authProposalId, true);

        vm.prank(voter2);
        council.executeProposal(
            authProposalId, address(council), abi.encodeCall(council.updateFastPass, (targets, selectors, authorized))
        );

        // Create proposal that benefits from fast-pass - only voter1 votes (100 power)
        bytes memory callData = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), callData);

        // Don't add voter2's vote - only voter1's auto-vote (100 power)
        // This is enough for fast-pass (40% = 70 power) but not for quorum (60% = 105 power)

        // Should pass with fast-pass threshold
        (,, bool passesWithFastPass) = council.countVotes(proposalId, address(target), MockTarget.setValue.selector);
        assertTrue(passesWithFastPass); // 100 power > 70 needed for fast-pass

        // Remove fast-pass authorization
        authorized[0] = false; // Revoke authorization

        vm.prank(voter1);
        uint256 revokeProposalId = council.proposeFastPassUpdate(targets, selectors, authorized);

        vm.prank(voter2);
        council.voteProposal(revokeProposalId, true);

        vm.prank(voter3);
        council.voteProposal(revokeProposalId, true);

        vm.prank(voter3);
        council.executeProposal(
            revokeProposalId, address(council), abi.encodeCall(council.updateFastPass, (targets, selectors, authorized))
        );

        // Now the original proposal should fail - needs quorum threshold (105 power)
        (,, bool failsAfterRevocation) = council.countVotes(proposalId, address(target), MockTarget.setValue.selector);
        assertFalse(failsAfterRevocation); // Only 100 power, but now needs 105
    }

    function _boolArray(bool value) internal pure returns (bool[] memory) {
        bool[] memory arr = new bool[](1);
        arr[0] = value;
        return arr;
    }
}
