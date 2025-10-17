// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/governance/simple-council/SimpleAdminCouncil.sol";
import "../../src/access/AccessControl.sol";
import "../../src/access/Ownable.sol";

// Concrete targets to be administered by the council
contract OwnableTarget is Ownable {}

contract AccessControlTarget is AccessControl {}

contract SimpleAdminCouncilTest is Test {
    // Actors
    address public alice; // voter1 (proposer)
    address public bob; // voter2 (executor)
    address public carol; // voter3
    address public dan; // non-voter
    address public erin; // another address

    // System under test
    SimpleAdminCouncil public council;
    OwnableTarget public ownableTarget;
    AccessControlTarget public accessTarget;

    bytes32 constant ROLE = keccak256("TEST_ROLE");

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dan = makeAddr("dan");
        erin = makeAddr("erin");

        address[] memory voters = new address[](3);
        voters[0] = alice;
        voters[1] = bob;
        voters[2] = carol;
        council = new SimpleAdminCouncil(voters);

        // Deploy targets and transfer ownership to the council so it has admin rights
        ownableTarget = new OwnableTarget();
        accessTarget = new AccessControlTarget();
        ownableTarget.transferOwnership(address(council));
        accessTarget.transferOwnership(address(council));

        // Sanity
        assertEq(ownableTarget.owner(), address(council));
        assertEq(accessTarget.owner(), address(council));
    }

    function _nextProposalId() internal view returns (uint256) {
        return council.nextProposalId();
    }

    function testProposeTransferOwnershipAndExecute() public {
        uint256 pid = _nextProposalId();
        vm.prank(alice);
        council.proposeTransferOwnership(address(ownableTarget), erin);

        // Execute by bob (different voter) to add executor yes-vote and pass quorum (2/3)
        bytes memory data = abi.encodeWithSelector(Ownable.transferOwnership.selector, erin);
        vm.prank(bob);
        council.executeProposal(pid, address(ownableTarget), data);

        assertEq(ownableTarget.owner(), erin);
    }

    function testProposeStartOwnershipTransferAndCancel() public {
        // startOwnershipTransfer -> set pendingOwner
        uint256 pidStart = _nextProposalId();
        vm.prank(alice);
        council.proposeStartOwnershipTransfer(address(ownableTarget), erin);

        bytes memory dataStart = abi.encodeWithSelector(Ownable.startOwnershipTransfer.selector, erin);
        vm.prank(bob);
        council.executeProposal(pidStart, address(ownableTarget), dataStart);
        assertEq(ownableTarget.pendingOwner(), erin);

        // cancelOwnershipTransfer -> clear pendingOwner
        uint256 pidCancel = _nextProposalId();
        vm.prank(alice);
        council.proposeCancelOwnershipTransfer(address(ownableTarget));

        bytes memory dataCancel = abi.encodeWithSelector(Ownable.cancelOwnershipTransfer.selector);
        vm.prank(bob);
        council.executeProposal(pidCancel, address(ownableTarget), dataCancel);
        assertEq(ownableTarget.pendingOwner(), address(0));
    }

    function testProposeGrantRoleAndRevokeRole() public {
        // Initially no role
        assertFalse(accessTarget.hasRole(ROLE, erin));

        // Grant role
        uint256 pidGrant = _nextProposalId();
        vm.prank(alice);
        council.proposeGrantRole(address(accessTarget), ROLE, erin);

        bytes memory dataGrant = abi.encodeWithSelector(IAccessControl.grantRole.selector, ROLE, erin);
        vm.prank(bob);
        council.executeProposal(pidGrant, address(accessTarget), dataGrant);
        assertTrue(accessTarget.hasRole(ROLE, erin));
        assertEq(accessTarget.roleMemberCount(ROLE), 1);

        // Revoke role
        uint256 pidRevoke = _nextProposalId();
        vm.prank(alice);
        council.proposeRevokeRole(address(accessTarget), ROLE, erin);

        bytes memory dataRevoke = abi.encodeWithSelector(IAccessControl.revokeRole.selector, ROLE, erin);
        vm.prank(bob);
        council.executeProposal(pidRevoke, address(accessTarget), dataRevoke);
        assertFalse(accessTarget.hasRole(ROLE, erin));
        assertEq(accessTarget.roleMemberCount(ROLE), 0);
    }

    function testProposeGrantRolesAndRevokeRoles() public {
        address[] memory accounts = new address[](2);
        accounts[0] = dan;
        accounts[1] = erin;

        uint256 pidGrant = _nextProposalId();
        vm.prank(alice);
        council.proposeGrantRoles(address(accessTarget), ROLE, accounts);

        bytes memory dataGrant = abi.encodeWithSelector(IAccessControl.grantRoles.selector, ROLE, accounts);
        vm.prank(bob);
        council.executeProposal(pidGrant, address(accessTarget), dataGrant);

        assertTrue(accessTarget.hasRole(ROLE, dan));
        assertTrue(accessTarget.hasRole(ROLE, erin));
        assertEq(accessTarget.roleMemberCount(ROLE), 2);

        uint256 pidRevoke = _nextProposalId();
        vm.prank(alice);
        council.proposeRevokeRoles(address(accessTarget), ROLE, accounts);

        bytes memory dataRevoke = abi.encodeWithSelector(IAccessControl.revokeRoles.selector, ROLE, accounts);
        vm.prank(bob);
        council.executeProposal(pidRevoke, address(accessTarget), dataRevoke);

        assertFalse(accessTarget.hasRole(ROLE, dan));
        assertFalse(accessTarget.hasRole(ROLE, erin));
        assertEq(accessTarget.roleMemberCount(ROLE), 0);
    }

    function testProposeSetRoleAdmin() public {
        // Set role admin to alice (arbitrary)
        uint256 pid = _nextProposalId();
        vm.prank(alice);
        council.proposeSetRoleAdmin(address(accessTarget), ROLE, alice);

        bytes memory data = abi.encodeWithSelector(IAccessControl.setRoleAdmin.selector, ROLE, alice);
        vm.prank(bob);
        council.executeProposal(pid, address(accessTarget), data);

        assertEq(accessTarget.roleAdmin(ROLE), alice);
    }
}
