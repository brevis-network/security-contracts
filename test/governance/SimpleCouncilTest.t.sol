// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/governance/simple-council/SimpleCouncil.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock target contract for external calls
contract MockTarget {
    uint256 public value;
    bool public flag;

    event ValueSet(uint256 newValue);

    function setValue(uint256 _value) external {
        value = _value;
        emit ValueSet(_value);
    }

    function revertingFunction() external pure {
        revert("Mock revert");
    }
}

// ERC20 that always returns false for transfer without changing balances
contract FalseReturnToken is ERC20 {
    constructor() ERC20("FalseReturn", "FRET") {}

    function transfer(address to, uint256 amount) public pure override returns (bool) {
        to;
        amount; // silence warnings
        return false;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SimpleCouncilTest is Test {
    SimpleCouncil public council;
    address public alice;
    address public bob;
    address public carol;
    address public dan;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dan = makeAddr("dan");

        address[] memory voters = new address[](3);
        voters[0] = alice;
        voters[1] = bob;
        voters[2] = carol;

        // For 3 voters, 60% quorum => 2 required; activePeriod 0 => default 86400
        council = new SimpleCouncil(voters, 2, 0);
    }

    function testConstructorAndGetters() public view {
        address[] memory voters = council.getVoters();
        assertEq(voters.length, 3);
        assertEq(voters[0], alice);
        assertEq(voters[1], bob);
        assertEq(voters[2], carol);
        assertTrue(council.isVoter(alice));
        assertTrue(council.isVoter(bob));
        assertTrue(council.isVoter(carol));
        assertFalse(council.isVoter(dan));
    }

    function testConstructorEmptyVotersReverts() public {
        address[] memory empty;
        vm.expectRevert(SimpleCouncil.EmptyVoters.selector);
        new SimpleCouncil(empty, 1, 0);
    }

    function testCreateProposalByVoterEmitsAndAutoVotes() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data);
        assertEq(proposalId, 0);
        assertTrue(council.getVote(proposalId, alice));
    }

    function testCreateProposalByNonVoterReverts() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 1);

        vm.prank(dan);
        vm.expectRevert(SimpleCouncil.OnlyVoterCanCreateProposal.selector);
        council.createProposal(address(target), data);
    }

    function testVoteAndCountQuorumWith3Voters() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 100);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data); // alice auto-yes

        vm.prank(bob);
        council.voteProposal(proposalId, true);

        (uint256 yesVotes, bool hasQuorum) = council.countVotes(proposalId);
        assertEq(yesVotes, 2);
        assertTrue(hasQuorum); // 2/3 >= 60%
    }

    function testVoteByNonVoterReverts() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 7);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.prank(dan);
        vm.expectRevert(SimpleCouncil.OnlyVoterCanVote.selector);
        council.voteProposal(proposalId, true);
    }

    function testVoteAfterDeadlineReverts() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 7);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data);

        // Warp past the deadline
        vm.warp(block.timestamp + council.activePeriod() + 1);

        vm.prank(bob);
        vm.expectRevert(SimpleCouncil.DeadlinePassed.selector);
        council.voteProposal(proposalId, true);
    }

    function testExecuteRequiresQuorumWith4Voters() public {
        // New council with 4 voters: 60% requires 3 yes votes
        address[] memory voters = new address[](4);
        voters[0] = alice;
        voters[1] = bob;
        voters[2] = carol;
        voters[3] = dan;
        // For 4 voters, 60% quorum rounds up to 3 required
        SimpleCouncil council4 = new SimpleCouncil(voters, 3, 0);

        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 11);

        vm.prank(alice);
        uint256 proposalId = council4.createProposal(address(target), data); // alice yes (1)

        // Execute with bob: executor auto-yes (2), still below 3 required
        vm.prank(bob);
        vm.expectRevert(SimpleCouncil.NotEnoughVotes.selector);
        council4.executeProposal(proposalId, address(target), data);

        // carol votes yes (2 from voters + executor will be 3)
        vm.prank(carol);
        council4.voteProposal(proposalId, true);

        vm.prank(bob);
        council4.executeProposal(proposalId, address(target), data);
        assertEq(target.value(), 11);

        // Subsequent execute attempts should revert due to deadline reset to 0
        vm.prank(bob);
        vm.expectRevert(SimpleCouncil.DeadlinePassed.selector);
        council4.executeProposal(proposalId, address(target), data);
    }

    function testExecuteDataHashMismatchReverts() public {
        MockTarget target = new MockTarget();
        bytes memory data1 = abi.encodeWithSignature("setValue(uint256)", 1);
        bytes memory data2 = abi.encodeWithSignature("setValue(uint256)", 2);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data1);

        // Bob votes yes to ensure quorum (2/3)
        vm.prank(bob);
        council.voteProposal(proposalId, true);

        vm.prank(alice);
        vm.expectRevert(SimpleCouncil.DataHashMismatch.selector);
        council.executeProposal(proposalId, address(target), data2);
    }

    function testExecuteAfterDeadlineReverts() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 5);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.prank(bob);
        council.voteProposal(proposalId, true);

        // Move past deadline
        vm.warp(block.timestamp + council.activePeriod() + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleCouncil.DeadlinePassed.selector);
        council.executeProposal(proposalId, address(target), data);
    }

    function testExecuteExternalCallFailureBubblesReason() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("revertingFunction()");

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.prank(bob);
        council.voteProposal(proposalId, true);

        vm.prank(carol);
        // External call now bubbles the exact revert data from target
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Mock revert"));
        council.executeProposal(proposalId, address(target), data);
    }

    function testTokenTransferViaProposal() public {
        // Deploy token and fund the council
        MockToken token = new MockToken();

        // Move some tokens to the council
        token.transfer(address(council), 1_000 * 10 ** token.decimals());

        // Propose token transfer from council to alice
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", alice, 100 * 10 ** token.decimals());

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(token), data);

        // Have bob vote yes to reach quorum (2/3)
        vm.prank(bob);
        council.voteProposal(proposalId, true);

        // Execute
        vm.prank(carol);
        council.executeProposal(proposalId, address(token), data);

        assertEq(token.balanceOf(alice), 100 * 10 ** token.decimals());
        // Council balance decreased accordingly
        assertEq(token.balanceOf(address(council)), 900 * 10 ** token.decimals());
    }

    function testGetVoteDefaultFalse() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 123);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data);

        assertFalse(council.getVote(proposalId, bob));
    }

    function testOnlyVoterCanExecuteReverts() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 9);

        vm.prank(alice);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.prank(dan);
        vm.expectRevert(SimpleCouncil.OnlyVoterCanExecuteProposal.selector);
        council.executeProposal(proposalId, address(target), data);
    }

    function testQuorumBoundaryWith5Voters() public {
        // 5 voters -> 60% requires 3 yes votes
        address[] memory voters = new address[](5);
        voters[0] = alice;
        voters[1] = bob;
        voters[2] = carol;
        voters[3] = dan;
        voters[4] = makeAddr("erin");
        // For 5 voters, 60% quorum rounds up to 3 required
        SimpleCouncil council5 = new SimpleCouncil(voters, 3, 0);

        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 77);

        // Alice creates -> auto-yes (1)
        vm.prank(alice);
        uint256 pid = council5.createProposal(address(target), data);

        // Bob yes (2), Carol yes (3) -> reaches 3/5 = 60%
        vm.prank(bob);
        council5.voteProposal(pid, true);
        vm.prank(carol);
        council5.voteProposal(pid, true);

        // Dan executes -> executor auto-yes (4) but already had quorum before execution
        vm.prank(dan);
        council5.executeProposal(pid, address(target), data);
        assertEq(target.value(), 77);
    }

    function testVoteFlipAffectsQuorum() public {
        MockTarget target = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 55);

        vm.prank(alice);
        uint256 pid = council.createProposal(address(target), data); // alice yes (1)

        vm.prank(bob);
        council.voteProposal(pid, true); // yes (2)

        (uint256 yesVotes, bool hasQuorum) = council.countVotes(pid);
        assertEq(yesVotes, 2);
        assertTrue(hasQuorum);

        // Bob flips to no
        vm.prank(bob);
        council.voteProposal(pid, false);
        (yesVotes, hasQuorum) = council.countVotes(pid);
        assertEq(yesVotes, 1);
        assertFalse(hasQuorum);
    }

    function testProposalIdIncrements() public {
        MockTarget target = new MockTarget();
        bytes memory data1 = abi.encodeWithSignature("setValue(uint256)", 1);
        bytes memory data2 = abi.encodeWithSignature("setValue(uint256)", 2);

        vm.prank(alice);
        uint256 id1 = council.createProposal(address(target), data1);
        vm.prank(bob);
        uint256 id2 = council.createProposal(address(target), data2);
        assertEq(id1, 0);
        assertEq(id2, 1);
    }

    function testExecuteWithMismatchedTargetReverts() public {
        MockTarget target1 = new MockTarget();
        MockTarget target2 = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 101);

        vm.prank(alice);
        uint256 pid = council.createProposal(address(target1), data);
        vm.prank(bob);
        council.voteProposal(pid, true);

        vm.prank(carol);
        vm.expectRevert(SimpleCouncil.DataHashMismatch.selector);
        council.executeProposal(pid, address(target2), data);
    }

    function testTokenTransferFalseReturnDoesNotRevertButNoBalanceChange() public {
        FalseReturnToken token = new FalseReturnToken();
        // Fund council directly
        uint256 initial = 1_000 * 10 ** token.decimals();
        token.mint(address(council), initial);

        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", alice, 100);
        vm.prank(alice);
        uint256 pid = council.createProposal(address(token), data);
        vm.prank(bob);
        council.voteProposal(pid, true);

        vm.prank(carol);
        // External call returns (success=true, data=abi.encode(false)), so our execute does not revert
        council.executeProposal(pid, address(token), data);

        // Balances unchanged because token returned false and ignored the transfer
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(council)), initial);
    }
}
