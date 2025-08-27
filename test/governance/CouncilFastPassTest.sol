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
            IGovernanceCouncil.ProposalType.FastPassUpdate,
            address(0),
            abi.encode(_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
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
            IGovernanceCouncil.ProposalType.FastPassUpdate,
            address(0),
            abi.encode(_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
        );

        assertTrue(council.isFastPassAuthorized(address(target), MockTarget.setValue.selector));

        // Then remove authorization
        vm.prank(voter1);
        uint256 proposalId2 = council.proposeFastPassUpdate(
            _addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(false)
        );

        _executeProposal(
            proposalId2,
            IGovernanceCouncil.ProposalType.FastPassUpdate,
            address(0),
            abi.encode(_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(false))
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
            IGovernanceCouncil.ProposalType.FastPassUpdate,
            address(0),
            abi.encode(_addressArray(address(target)), _bytes4Array(bytes4(0)), _boolArray(true))
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
            IGovernanceCouncil.ProposalType.FastPassUpdate,
            address(0),
            abi.encode(_addressArray(address(target)), _bytes4Array(bytes4(0)), _boolArray(true))
        );

        // Add specific authorization for same function
        vm.prank(voter1);
        uint256 proposalId2 = council.proposeFastPassUpdate(
            _addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true)
        );

        _executeProposal(
            proposalId2,
            IGovernanceCouncil.ProposalType.FastPassUpdate,
            address(0),
            abi.encode(_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
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
            IGovernanceCouncil.ProposalType.FastPassUpdate,
            address(0),
            abi.encode(_addressArray(address(target)), _bytes4Array(MockTarget.setValue.selector), _boolArray(true))
        );

        // Create external proposal for setValue (should use fast-pass threshold)
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter2);
        uint256 proposalId = council.createProposal(address(target), data);

        // Should use fast-pass threshold (40%)
        (uint256 totalPower, uint256 yesVotes, bool pass) = council.countVotes(
            proposalId, IGovernanceCouncil.ProposalType.External, address(target), MockTarget.setValue.selector
        );

        assertEq(totalPower, TOTAL_POWER);
        assertEq(yesVotes, VOTER2_POWER); // Only voter2 voted (auto-vote)
        assertFalse(pass); // 50/175 = 28% < 40% fast-pass threshold

        // Add voter1's vote to reach fast-pass threshold
        vm.prank(voter1);
        council.voteProposal(proposalId, true);

        (totalPower, yesVotes, pass) = council.countVotes(
            proposalId, IGovernanceCouncil.ProposalType.External, address(target), MockTarget.setValue.selector
        );

        assertEq(yesVotes, VOTER1_POWER + VOTER2_POWER);
        assertTrue(pass); // 150/175 = 85% > 40% fast-pass threshold
    }

    function testQuorumThresholdWhenNoFastPass() public {
        // Create external proposal for setValue (no fast-pass authorization)
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Should use quorum threshold (60%)
        (uint256 totalPower, uint256 yesVotes, bool pass) = council.countVotes(
            proposalId, IGovernanceCouncil.ProposalType.External, address(target), MockTarget.setValue.selector
        );

        assertEq(yesVotes, VOTER1_POWER);
        assertFalse(pass); // 100/175 = 57% < 60% quorum threshold

        // Add voter2's vote to reach quorum threshold
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        (totalPower, yesVotes, pass) = council.countVotes(
            proposalId, IGovernanceCouncil.ProposalType.External, address(target), MockTarget.setValue.selector
        );

        assertEq(yesVotes, VOTER1_POWER + VOTER2_POWER);
        assertTrue(pass); // 150/175 = 85% > 60% quorum threshold
    }

    function testNonExternalProposalsUseQuorumThreshold() public {
        // Parameter update should always use quorum threshold
        vm.prank(voter1);
        uint256 proposalId = council.proposeParamUpdate(IGovernanceCouncil.Param.ActivePeriod, 10000);

        (, uint256 yesVotes, bool pass) =
            council.countVotes(proposalId, IGovernanceCouncil.ProposalType.ParamUpdate, address(0), bytes4(0));

        assertEq(yesVotes, VOTER1_POWER);
        assertFalse(pass); // Should use 60% quorum threshold, not 40% fast-pass
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                    HELPER FUNCTIONS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function _executeProposal(
        uint256 proposalId,
        IGovernanceCouncil.ProposalType proposalType,
        address target,
        bytes memory data
    ) internal {
        // Get enough votes to pass
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        vm.prank(voter1);
        council.executeProposal(proposalId, proposalType, target, data);
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

    function _boolArray(bool value) internal pure returns (bool[] memory) {
        bool[] memory arr = new bool[](1);
        arr[0] = value;
        return arr;
    }
}
