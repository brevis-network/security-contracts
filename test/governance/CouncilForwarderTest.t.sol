// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/governance/GovernanceCouncil.sol";
import "../../src/governance/proposal-forwarders/AdminProposalForwarder.sol";
import "../../src/governance/proposal-forwarders/forwarders/AccessControlForwarder.sol";
import "../../src/governance/proposal-forwarders/forwarders/ProxyAdminForwarder.sol";
import "../../src/access/interfaces/IOwnable.sol";
import "../../src/access/interfaces/IAccessControl.sol";
import "../../src/governance/proposal-forwarders/interfaces/IProxyAdmin.sol";

// Mock contracts for testing
contract MockOwnable {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external {
        owner = newOwner;
    }
}

contract MockAccessControl {
    mapping(bytes32 => mapping(address => bool)) public hasRole;

    function grantRole(bytes32 role, address account) external {
        hasRole[role][account] = true;
    }

    function grantRoles(bytes32 role, address[] calldata accounts) external {
        for (uint256 i = 0; i < accounts.length; i++) {
            hasRole[role][accounts[i]] = true;
        }
    }

    function revokeRole(bytes32 role, address account) external {
        hasRole[role][account] = false;
    }

    function revokeRoles(bytes32 role, address[] calldata accounts) external {
        for (uint256 i = 0; i < accounts.length; i++) {
            hasRole[role][accounts[i]] = false;
        }
    }
}

contract MockProxyAdmin {
    mapping(address => address) public proxyAdmins;
    mapping(address => address) public proxyImplementations;

    function changeProxyAdmin(address _proxy, address _newAdmin) external {
        proxyAdmins[_proxy] = _newAdmin;
    }

    function upgrade(address _proxy, address _implementation) external {
        proxyImplementations[_proxy] = _implementation;
    }

    function upgradeAndCall(address _proxy, address _implementation, bytes calldata /* _data */ ) external {
        proxyImplementations[_proxy] = _implementation;
        // In real implementation, would make call to proxy with _data
    }
}

contract CouncilForwarderTest is Test {
    GovernanceCouncil public council;
    AdminProposalForwarder public forwarder;

    MockOwnable public mockOwnable;
    MockAccessControl public mockAccessControl;
    MockProxyAdmin public mockProxyAdmin;

    address public deployer = makeAddr("deployer");
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");
    address public voter3 = makeAddr("voter3");
    address public forwarder1 = makeAddr("forwarder1");
    address public newOwner = makeAddr("newOwner");
    address public account1 = makeAddr("account1");
    address public account2 = makeAddr("account2");
    address public proxy = makeAddr("proxy");
    address public proxyAdmin = makeAddr("proxyAdmin");
    address public newAdmin = makeAddr("newAdmin");
    address public implementation = makeAddr("implementation");

    bytes32 public constant ROLE = keccak256("TEST_ROLE");

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy unified forwarder first (no council set yet, initializer is deployer)
        forwarder = new AdminProposalForwarder(address(0), deployer);

        // Deploy mock contracts
        mockOwnable = new MockOwnable();
        mockAccessControl = new MockAccessControl();
        mockProxyAdmin = new MockProxyAdmin();

        // Setup council constructor parameters
        address[] memory voters = new address[](3);
        uint256[] memory weights = new uint256[](3);
        voters[0] = voter1;
        voters[1] = voter2;
        voters[2] = voter3;
        weights[0] = 100;
        weights[1] = 100;
        weights[2] = 100;

        address[] memory forwarders = new address[](1);
        forwarders[0] = address(forwarder);

        // Deploy council with all parameters
        council = new GovernanceCouncil(
            voters,
            weights,
            forwarders,
            3600, // 1 hour active period
            60 // 60% quorum threshold
        );

        // Initialize forwarder with council
        forwarder.initCouncil(council);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════
    //                                   FORWARDER BASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════════

    function test_ProposalForwarderBase_InitCouncil_Success() public {
        // Deploy new forwarder
        vm.prank(deployer);
        AdminProposalForwarder newForwarder = new AdminProposalForwarder(address(0), deployer);

        assertEq(address(newForwarder.council()), address(0));

        vm.prank(deployer);
        newForwarder.initCouncil(council);

        assertEq(address(newForwarder.council()), address(council));
    }

    function test_ProposalForwarderBase_InitCouncil_OnlyInitializer() public {
        vm.prank(deployer);
        AdminProposalForwarder newForwarder = new AdminProposalForwarder(address(0), deployer);

        vm.prank(voter1);
        vm.expectRevert(ProposalForwarderBase.OnlyInitializerCanInit.selector);
        newForwarder.initCouncil(council);
    }

    function test_ProposalForwarderBase_InitCouncil_AlreadySet() public {
        vm.expectRevert(ProposalForwarderBase.CouncilAddressAlreadySet.selector);
        vm.prank(deployer);
        forwarder.initCouncil(council);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════
    //                                ACCESS CONTROL FORWARDER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════════

    function test_AccessControlForwarder_ProposeTransferOwnership() public {
        vm.expectEmit(true, true, true, true);
        emit AccessControlForwarder.TransferOwnershipProposed(0, address(mockOwnable), newOwner);

        // voter1 calls the forwarder function - voter1 must be a voter for this to work
        vm.prank(voter1);
        forwarder.proposeTransferOwnership(address(mockOwnable), newOwner);

        // Verify proposal was created - check the public fields
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);

        assertTrue(dataHash != bytes32(0)); // Data hash should be non-zero
        assertGt(deadline, block.timestamp); // Deadline should be in the future
        assertEq(council.nextProposalId(), 1); // Next proposal ID should be 1
    }

    function test_AccessControlForwarder_ProposeGrantRole() public {
        vm.expectEmit(true, true, true, true);
        emit AccessControlForwarder.GrantRoleProposed(0, address(mockAccessControl), ROLE, account1);

        vm.prank(voter1);
        forwarder.proposeGrantRole(address(mockAccessControl), ROLE, account1);

        // Verify proposal was created
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);
        assertTrue(dataHash != bytes32(0));
        assertGt(deadline, block.timestamp);
    }

    function test_AccessControlForwarder_ProposeGrantRoles() public {
        address[] memory accounts = new address[](2);
        accounts[0] = account1;
        accounts[1] = account2;

        vm.expectEmit(true, true, true, true);
        emit AccessControlForwarder.GrantRolesProposed(0, address(mockAccessControl), ROLE, accounts);

        vm.prank(voter1);
        forwarder.proposeGrantRoles(address(mockAccessControl), ROLE, accounts);

        // Verify proposal was created
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);
        assertTrue(dataHash != bytes32(0));
        assertGt(deadline, block.timestamp);
    }

    function test_AccessControlForwarder_ProposeRevokeRole() public {
        vm.expectEmit(true, true, true, true);
        emit AccessControlForwarder.RevokeRoleProposed(0, address(mockAccessControl), ROLE, account1);

        vm.prank(voter1);
        forwarder.proposeRevokeRole(address(mockAccessControl), ROLE, account1);

        // Verify proposal was created
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);
        assertTrue(dataHash != bytes32(0));
        assertGt(deadline, block.timestamp);
    }

    function test_AccessControlForwarder_ProposeRevokeRoles() public {
        address[] memory accounts = new address[](2);
        accounts[0] = account1;
        accounts[1] = account2;

        vm.expectEmit(true, true, true, true);
        emit AccessControlForwarder.RevokeRolesProposed(0, address(mockAccessControl), ROLE, accounts);

        vm.prank(voter1);
        forwarder.proposeRevokeRoles(address(mockAccessControl), ROLE, accounts);

        // Verify proposal was created
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);
        assertTrue(dataHash != bytes32(0));
        assertGt(deadline, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════
    //                                  PROXY ADMIN FORWARDER TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════════

    function test_ProxyAdminForwarder_ProposeChangeProxyAdmin() public {
        vm.expectEmit(true, true, true, true);
        emit ProxyAdminForwarder.ChangeProxyAdminProposed(0, proxyAdmin, proxy, newAdmin);

        vm.prank(voter1);
        forwarder.proposeChangeProxyAdmin(proxyAdmin, proxy, newAdmin);

        // Verify proposal was created
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);
        assertTrue(dataHash != bytes32(0));
        assertGt(deadline, block.timestamp);
    }

    function test_ProxyAdminForwarder_ProposeUpgrade() public {
        vm.expectEmit(true, true, true, true);
        emit ProxyAdminForwarder.UpgradeProposed(0, proxyAdmin, proxy, implementation);

        vm.prank(voter1);
        forwarder.proposeUpgrade(proxyAdmin, proxy, implementation);

        // Verify proposal was created
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);
        assertTrue(dataHash != bytes32(0));
        assertGt(deadline, block.timestamp);
    }

    function test_ProxyAdminForwarder_ProposeUpgradeAndCall() public {
        bytes memory callData = abi.encodeWithSignature("initialize(address)", account1);

        vm.expectEmit(true, true, true, true);
        emit ProxyAdminForwarder.UpgradeAndCallProposed(0, proxyAdmin, proxy, implementation, callData);

        vm.prank(voter1);
        forwarder.proposeUpgradeAndCall(proxyAdmin, proxy, implementation, callData);

        // Verify proposal was created
        (bytes32 dataHash, uint256 deadline) = council.proposals(0);
        assertTrue(dataHash != bytes32(0));
        assertGt(deadline, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════
    //                                 INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════════════

    function test_Integration_AccessControlForwarderFullWorkflow() public {
        // 1. Forwarder creates proposal
        vm.prank(voter1);
        forwarder.proposeTransferOwnership(address(mockOwnable), newOwner);

        // 2. Voters vote on proposal
        vm.prank(voter2); // voter1 already voted when creating the proposal
        council.voteProposal(0, true);

        // 3. Execute proposal with the correct parameters
        bytes memory data = abi.encodeWithSelector(IOwnable.transferOwnership.selector, newOwner);
        vm.prank(voter1);
        council.executeProposal(0, address(mockOwnable), data);

        // 4. Verify execution worked
        assertEq(mockOwnable.owner(), newOwner);
    }

    function test_Integration_ProxyAdminForwarderFullWorkflow() public {
        // 1. Forwarder creates proposal for changing proxy admin
        vm.prank(voter1);
        forwarder.proposeChangeProxyAdmin(proxyAdmin, proxy, newAdmin);

        // 2. Voters vote on proposal
        vm.prank(voter2); // voter1 already voted when creating the proposal
        council.voteProposal(0, true);

        // 3. Execute proposal with the correct parameters
        bytes memory data = abi.encodeWithSelector(IProxyAdmin.changeProxyAdmin.selector, proxy, newAdmin);
        vm.prank(voter1);
        // This should succeed as the call will be made to the proxyAdmin address
        // even though it doesn't implement the interface, the call will complete
        council.executeProposal(0, proxyAdmin, data);

        // The call completed successfully, though proxyAdmin doesn't actually implement the interface
    }

    function test_Integration_MultipleProposalsFromDifferentForwarders() public {
        // Access control forwarder creates proposal
        vm.prank(voter1);
        forwarder.proposeGrantRole(address(mockAccessControl), ROLE, account1);

        // Proxy admin forwarder creates proposal
        vm.prank(voter2);
        forwarder.proposeUpgrade(proxyAdmin, proxy, implementation);

        // Verify both proposals exist
        (bytes32 dataHash1,) = council.proposals(0);
        (bytes32 dataHash2,) = council.proposals(1);

        assertTrue(dataHash1 != bytes32(0));
        assertTrue(dataHash2 != bytes32(0));
        assertEq(council.nextProposalId(), 2);
    }

    function test_Integration_ForwarderCannotCreateProposalWithoutCouncilInit() public {
        vm.prank(deployer);
        AdminProposalForwarder uninitForwarder = new AdminProposalForwarder(address(0), deployer);

        // Should revert because council is not initialized (address(0))
        vm.prank(forwarder1);
        vm.expectRevert();
        uninitForwarder.proposeTransferOwnership(address(mockOwnable), newOwner);
    }

    function test_Integration_OnlyTrustedForwardersCanCreateProposals() public {
        vm.prank(deployer);
        AdminProposalForwarder untrustedForwarder = new AdminProposalForwarder(address(0), deployer);
        vm.prank(deployer);
        untrustedForwarder.initCouncil(council);

        // This should fail because the untrusted proposal forwarder is not in the proposerForwarders set
        vm.prank(voter1);
        vm.expectRevert(IGovernanceCouncil.InvalidProposalForwarder.selector);
        untrustedForwarder.proposeTransferOwnership(address(mockOwnable), newOwner);
    }

    function testNonVoterCannotUseForwarder() public {
        address nonVoter = makeAddr("nonVoter");

        // Non-voter should not be able to use forwarder to create proposals
        vm.prank(nonVoter);
        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanCreateProposal.selector);
        forwarder.proposeTransferOwnership(address(mockOwnable), makeAddr("newOwner"));

        // Verify the same for other forwarder functions
        vm.prank(nonVoter);
        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanCreateProposal.selector);
        forwarder.proposeGrantRole(address(mockAccessControl), bytes32("ADMIN"), nonVoter);

        vm.prank(nonVoter);
        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanCreateProposal.selector);
        forwarder.proposeUpgrade(address(mockProxyAdmin), makeAddr("proxy"), makeAddr("newImplementation"));

        // Test the ProxyAdmin-owned functions as well
        vm.prank(nonVoter);
        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanCreateProposal.selector);
        forwarder.proposeChangeProxyAdmin(address(mockProxyAdmin), makeAddr("proxy"), makeAddr("newAdmin"));

        vm.prank(nonVoter);
        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanCreateProposal.selector);
        forwarder.proposeUpgrade(address(mockProxyAdmin), makeAddr("proxy"), makeAddr("newImplementation"));

        vm.prank(nonVoter);
        vm.expectRevert(IGovernanceCouncil.OnlyVoterCanCreateProposal.selector);
        forwarder.proposeUpgradeAndCall(address(mockProxyAdmin), makeAddr("proxy"), makeAddr("newImplementation"), "");
    }
}
