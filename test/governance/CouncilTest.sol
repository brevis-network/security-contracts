// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/governance/GovernanceCouncil.sol";
import "../../src/governance/IGovernanceCouncil.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock target contract for external calls
contract MockTarget {
    uint256 public value;
    bool public flag;
    address public owner;

    event ValueSet(uint256 newValue);
    event FlagSet(bool newFlag);
    event OwnerSet(address newOwner);

    function setValue(uint256 _value) external {
        value = _value;
        emit ValueSet(_value);
    }

    function setFlag(bool _flag) external {
        flag = _flag;
        emit FlagSet(_flag);
    }

    function setOwner(address _owner) external {
        owner = _owner;
        emit OwnerSet(_owner);
    }

    function revertingFunction() external pure {
        revert("Mock revert");
    }
}

contract CouncilTest is Test {
    GovernanceCouncil public council;
    MockToken public token;
    MockTarget public target;

    // Test addresses
    address public voter1;
    address public voter2;
    address public voter3;
    address public nonVoter;
    address public forwarder1;

    // Voting powers
    uint256 public constant VOTER1_POWER = 100;
    uint256 public constant VOTER2_POWER = 50;
    uint256 public constant VOTER3_POWER = 25;
    uint256 public constant TOTAL_POWER = VOTER1_POWER + VOTER2_POWER + VOTER3_POWER; // 175

    // Governance parameters
    uint256 public constant ACTIVE_PERIOD = 7200; // 2 hours
    uint256 public constant QUORUM_THRESHOLD = 60; // 60%
    uint256 public constant FAST_PASS_THRESHOLD = 40; // 40%

    function setUp() public virtual {
        // Create test addresses
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");
        nonVoter = makeAddr("nonVoter");
        forwarder1 = makeAddr("forwarder1");

        // Setup arrays for constructor
        address[] memory voters = new address[](3);
        voters[0] = voter1;
        voters[1] = voter2;
        voters[2] = voter3;

        uint256[] memory powers = new uint256[](3);
        powers[0] = VOTER1_POWER;
        powers[1] = VOTER2_POWER;
        powers[2] = VOTER3_POWER;

        address[] memory forwarders = new address[](1);
        forwarders[0] = forwarder1;

        // Deploy contracts
        council =
            new GovernanceCouncil(voters, powers, forwarders, ACTIVE_PERIOD, QUORUM_THRESHOLD, FAST_PASS_THRESHOLD);

        token = new MockToken();
        target = new MockTarget();

        // Transfer some tokens to council for testing
        token.transfer(address(council), 1000 * 10 ** token.decimals());

        // Send some ETH to council for testing
        vm.deal(address(council), 10 ether);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                    CONSTRUCTOR TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testConstructor() public view {
        // Check voters are set correctly
        (address[] memory addrs, uint256[] memory powers,) = council.getVoters();
        assertEq(addrs.length, 3);
        assertEq(addrs[0], voter1);
        assertEq(addrs[1], voter2);
        assertEq(addrs[2], voter3);
        assertEq(powers[0], VOTER1_POWER);
        assertEq(powers[1], VOTER2_POWER);
        assertEq(powers[2], VOTER3_POWER);

        // Check parameters
        assertEq(council.params(IGovernanceCouncil.Param.ActivePeriod), ACTIVE_PERIOD);
        assertEq(council.params(IGovernanceCouncil.Param.QuorumThreshold), QUORUM_THRESHOLD);
        assertEq(council.params(IGovernanceCouncil.Param.FastPassThreshold), FAST_PASS_THRESHOLD);

        // Check forwarders
        assertTrue(council.isProposalForwarder(forwarder1));
        assertEq(council.getProposalForwarders().length, 1);
        assertEq(council.getProposalForwarders()[0], forwarder1);
    }

    function testConstructorInvalidLength() public {
        address[] memory voters = new address[](2);
        uint256[] memory powers = new uint256[](1); // Mismatched length
        address[] memory forwarders = new address[](0);

        vm.expectRevert(IGovernanceCouncil.InvalidLength.selector);
        new GovernanceCouncil(voters, powers, forwarders, ACTIVE_PERIOD, QUORUM_THRESHOLD, FAST_PASS_THRESHOLD);
    }

    function testConstructorEmptyVoters() public {
        address[] memory voters = new address[](0);
        uint256[] memory powers = new uint256[](0);
        address[] memory forwarders = new address[](0);

        vm.expectRevert(IGovernanceCouncil.InvalidLength.selector);
        new GovernanceCouncil(voters, powers, forwarders, ACTIVE_PERIOD, QUORUM_THRESHOLD, FAST_PASS_THRESHOLD);
    }

    function testConstructorInvalidActivePeriod() public {
        address[] memory voters = new address[](1);
        voters[0] = voter1;
        uint256[] memory powers = new uint256[](1);
        powers[0] = 100;
        address[] memory forwarders = new address[](0);

        // Too short
        vm.expectRevert(IGovernanceCouncil.InvalidActivePeriod.selector);
        new GovernanceCouncil(
            voters,
            powers,
            forwarders,
            3000, // < MIN_ACTIVE_PERIOD (3600)
            QUORUM_THRESHOLD,
            FAST_PASS_THRESHOLD
        );

        // Too long
        vm.expectRevert(IGovernanceCouncil.InvalidActivePeriod.selector);
        new GovernanceCouncil(
            voters,
            powers,
            forwarders,
            2500000, // > MAX_ACTIVE_PERIOD (2419200)
            QUORUM_THRESHOLD,
            FAST_PASS_THRESHOLD
        );
    }

    function testConstructorInvalidThreshold() public {
        address[] memory voters = new address[](1);
        voters[0] = voter1;
        uint256[] memory powers = new uint256[](1);
        powers[0] = 100;
        address[] memory forwarders = new address[](0);

        // Quorum threshold >= 100
        vm.expectRevert(IGovernanceCouncil.InvalidThreshold.selector);
        new GovernanceCouncil(
            voters,
            powers,
            forwarders,
            ACTIVE_PERIOD,
            100, // >= THRESHOLD_DECIMAL
            FAST_PASS_THRESHOLD
        );

        // FastPass > Quorum
        vm.expectRevert(IGovernanceCouncil.InvalidThreshold.selector);
        new GovernanceCouncil(
            voters,
            powers,
            forwarders,
            ACTIVE_PERIOD,
            40,
            50 // > quorum threshold
        );
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                    EXTERNAL PROPOSAL TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testCreateExternalProposal() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        assertEq(proposalId, 0);
        assertEq(council.nextProposalId(), 1);

        // Check proposer automatically voted yes
        assertTrue(council.getVote(proposalId, voter1));
    }

    function testCreateExternalProposalInvalidSelector() public {
        bytes memory data = new bytes(2); // Too short

        vm.expectRevert(IGovernanceCouncil.InvalidSelector.selector);
        vm.prank(voter1);
        council.createProposal(address(target), data);
    }

    function testCreateExternalProposalNonVoter() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanCreateProposal.selector);
        vm.prank(nonVoter);
        council.createProposal(address(target), data);
    }

    function testCreateExternalProposalViaForwarder() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(forwarder1);
        uint256 proposalId = council.createProposal(voter1, address(target), data);

        assertEq(proposalId, 0);
        assertTrue(council.getVote(proposalId, voter1));
    }

    function testCreateExternalProposalViaInvalidProposalForwarder() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.expectRevert(IGovernanceCouncil.InvalidProposalForwarder.selector);
        vm.prank(nonVoter);
        council.createProposal(voter1, address(target), data);
    }

    function testCreateExternalProposalViaForwarderInvalidSelector() public {
        bytes memory data = new bytes(2); // Too short

        vm.expectRevert(IGovernanceCouncil.InvalidSelector.selector);
        vm.prank(forwarder1);
        council.createProposal(voter1, address(target), data);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                        VOTING TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testVoteProposal() public {
        // Create proposal
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Vote yes
        vm.prank(voter2);
        council.voteProposal(proposalId, true);
        assertTrue(council.getVote(proposalId, voter2));

        // Vote no
        vm.prank(voter3);
        council.voteProposal(proposalId, false);
        assertFalse(council.getVote(proposalId, voter3));

        // Change vote
        vm.prank(voter2);
        council.voteProposal(proposalId, false);
        assertFalse(council.getVote(proposalId, voter2));
    }

    function testVoteProposalNonVoter() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        vm.expectRevert(IGovernanceCouncil.InvalidCaller.selector);
        vm.prank(nonVoter);
        council.voteProposal(proposalId, true);
    }

    function testVoteProposalExpired() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Fast forward past deadline
        vm.warp(block.timestamp + ACTIVE_PERIOD + 1);

        vm.expectRevert(IGovernanceCouncil.DeadlinePassed.selector);
        vm.prank(voter2);
        council.voteProposal(proposalId, true);
    }

    function testVoteMultipleProposals() public {
        // Create proposals
        bytes memory data1 = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        bytes memory data2 = abi.encodeWithSelector(MockTarget.setFlag.selector, true);

        vm.prank(voter1);
        uint256 proposalId1 = council.createProposal(address(target), data1);

        vm.prank(voter2);
        uint256 proposalId2 = council.createProposal(address(target), data2);

        // Vote on multiple proposals
        uint256[] memory proposalIds = new uint256[](2);
        bool[] memory votes = new bool[](2);
        proposalIds[0] = proposalId1;
        proposalIds[1] = proposalId2;
        votes[0] = true;
        votes[1] = false;

        vm.prank(voter3);
        council.voteProposals(proposalIds, votes);

        assertTrue(council.getVote(proposalId1, voter3));
        assertFalse(council.getVote(proposalId2, voter3));
    }

    function testVoteMultipleProposalsInvalidLength() public {
        uint256[] memory proposalIds = new uint256[](2);
        bool[] memory votes = new bool[](1); // Mismatched length

        vm.expectRevert(IGovernanceCouncil.InvalidLength.selector);
        vm.prank(voter1);
        council.voteProposals(proposalIds, votes);
    }

    // ════════════════════════════════════════════════════════════════════════════════════════
    //                                    VOTE COUNTING TESTS
    // ════════════════════════════════════════════════════════════════════════════════════════

    function testCountVotesSimple() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Initial state: voter1 already voted yes (auto-vote)
        (uint256 totalPower, uint256 yesVotes) = council.countVotes(proposalId);
        assertEq(totalPower, TOTAL_POWER);
        assertEq(yesVotes, VOTER1_POWER);

        // Voter2 votes yes
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        (totalPower, yesVotes) = council.countVotes(proposalId);
        assertEq(totalPower, TOTAL_POWER);
        assertEq(yesVotes, VOTER1_POWER + VOTER2_POWER);

        // Voter3 votes no
        vm.prank(voter3);
        council.voteProposal(proposalId, false);

        (totalPower, yesVotes) = council.countVotes(proposalId);
        assertEq(totalPower, TOTAL_POWER);
        assertEq(yesVotes, VOTER1_POWER + VOTER2_POWER);
    }

    function testCountVotesWithThreshold() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(voter1);
        uint256 proposalId = council.createProposal(address(target), data);

        // Should use quorum threshold (no fast-pass authorization)
        (uint256 totalPower, uint256 yesVotes, bool pass) = council.countVotes(
            proposalId, IGovernanceCouncil.ProposalType.External, address(target), MockTarget.setValue.selector
        );

        assertEq(totalPower, TOTAL_POWER);
        assertEq(yesVotes, VOTER1_POWER);
        assertFalse(pass); // 100/175 = 57% < 60% quorum threshold

        // Add voter2's vote
        vm.prank(voter2);
        council.voteProposal(proposalId, true);

        (totalPower, yesVotes, pass) = council.countVotes(
            proposalId, IGovernanceCouncil.ProposalType.External, address(target), MockTarget.setValue.selector
        );

        assertEq(yesVotes, VOTER1_POWER + VOTER2_POWER);
        assertTrue(pass); // 150/175 = 85% > 60% quorum threshold
    }
}
