// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/governance/simple-council/SimpleAdminCouncil.sol";
import "../../src/access/AccessControl.sol";
import "../../src/access/Ownable.sol";
import "../../src/governance/proposal-forwarders/interfaces/IProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Concrete targets to be administered by the council
contract OwnableTarget is Ownable {}

contract AccessControlTarget is AccessControl {}

// Minimal ProxyAdmin-like contract owned by the council in tests
contract MockProxyAdmin is Ownable {
    mapping(address => address) public proxyAdmins;
    mapping(address => address) public proxyImplementations;
    bytes public lastData;

    function changeProxyAdmin(address _proxy, address _newAdmin) external onlyOwner {
        proxyAdmins[_proxy] = _newAdmin;
    }

    function upgrade(address _proxy, address _implementation) external onlyOwner {
        proxyImplementations[_proxy] = _implementation;
    }

    function upgradeAndCall(address _proxy, address _implementation, bytes calldata _data) external onlyOwner {
        proxyImplementations[_proxy] = _implementation;
        lastData = _data;
    }
}

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
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
    MockProxyAdmin public proxyAdminTarget;

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
        // For 3 voters, require 2 yes votes (≈60%); activePeriod 0 => default 86400
        council = new SimpleAdminCouncil(voters, 2, 0);

        // Deploy targets and transfer ownership to the council so it has admin rights
        ownableTarget = new OwnableTarget();
        accessTarget = new AccessControlTarget();
        proxyAdminTarget = new MockProxyAdmin();
        ownableTarget.transferOwnership(address(council));
        accessTarget.transferOwnership(address(council));
        proxyAdminTarget.transferOwnership(address(council));

        // Sanity
        assertEq(ownableTarget.owner(), address(council));
        assertEq(accessTarget.owner(), address(council));
        assertEq(proxyAdminTarget.owner(), address(council));
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

    // =========================== ProxyAdmin owner tests ===========================
    function testProposeChangeProxyAdminAndExecute() public {
        address proxy = makeAddr("proxy");
        address newAdmin = makeAddr("newAdmin");

        uint256 pid = _nextProposalId();
        vm.prank(alice);
        council.proposeChangeProxyAdmin(address(proxyAdminTarget), proxy, newAdmin);

        bytes memory data = abi.encodeWithSelector(IProxyAdmin.changeProxyAdmin.selector, proxy, newAdmin);
        vm.prank(bob);
        council.executeProposal(pid, address(proxyAdminTarget), data);

        assertEq(proxyAdminTarget.proxyAdmins(proxy), newAdmin);
    }

    function testProposeUpgradeAndExecute() public {
        address proxy = makeAddr("proxy");
        address implementation = makeAddr("impl");

        uint256 pid = _nextProposalId();
        vm.prank(alice);
        council.proposeUpgrade(address(proxyAdminTarget), proxy, implementation);

        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgrade.selector, proxy, implementation);
        vm.prank(bob);
        council.executeProposal(pid, address(proxyAdminTarget), data);

        assertEq(proxyAdminTarget.proxyImplementations(proxy), implementation);
    }

    function testProposeUpgradeAndCallAndExecute() public {
        address proxy = makeAddr("proxy");
        address implementation = makeAddr("impl");
        bytes memory callData = abi.encodeWithSignature("initialize(address)", erin);

        uint256 pid = _nextProposalId();
        vm.prank(alice);
        council.proposeUpgradeAndCall(address(proxyAdminTarget), proxy, implementation, callData);

        bytes memory data = abi.encodeWithSelector(IProxyAdmin.upgradeAndCall.selector, proxy, implementation, callData);
        vm.prank(bob);
        council.executeProposal(pid, address(proxyAdminTarget), data);

        assertEq(proxyAdminTarget.proxyImplementations(proxy), implementation);
        assertEq(proxyAdminTarget.lastData(), callData);
    }

    function testProposeERC20TransferAndExecute() public {
        // Deploy token and mint to council so it has balance to transfer
        MockToken token = new MockToken();
        uint256 amount = 1_000 ether;
        token.mint(address(council), amount);
        assertEq(token.balanceOf(address(council)), amount);

        uint256 pid = _nextProposalId();

        // Expect the proposal event
        vm.expectEmit(false, false, false, true, address(council));
        emit SimpleAdminCouncil.ERC20TransferProposed(pid, address(token), erin, 100 ether);

        // Propose ERC20 transfer (alice)
        vm.prank(alice);
        council.proposeERC20Transfer(address(token), erin, 100 ether);

        // Execute (bob) → adds yes vote and passes 2-of-3
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, erin, 100 ether);
        vm.prank(bob);
        council.executeProposal(pid, address(token), data);

        assertEq(token.balanceOf(erin), 100 ether);
        assertEq(token.balanceOf(address(council)), amount - 100 ether);
    }

    function testProposeERC20TransferFalseReturnDoesNotRevertButNoBalanceChange() public {
        FalseReturnToken token = new FalseReturnToken();
        uint256 initial = 1_000 ether;
        token.mint(address(council), initial);

        uint256 pid = _nextProposalId();
        vm.prank(alice);
        council.proposeERC20Transfer(address(token), erin, 100 ether);

        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", erin, 100 ether);
        vm.prank(bob);
        council.executeProposal(pid, address(token), data);

        // No revert and no balance change because token returned false and ignored the transfer
        assertEq(token.balanceOf(erin), 0);
        assertEq(token.balanceOf(address(council)), initial);
    }

    function testProposeERC20TransferInsufficientBalanceReverts() public {
        // Council has zero balance; OZ ERC20.transfer reverts on insufficient funds
        MockToken token = new MockToken();
        assertEq(token.balanceOf(address(council)), 0);

        uint256 pid = _nextProposalId();
        vm.prank(alice);
        council.proposeERC20Transfer(address(token), erin, 1 ether);

        bytes memory data = abi.encodeWithSelector(token.transfer.selector, erin, 1 ether);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", address(council), 0, 1 ether)
        );
        council.executeProposal(pid, address(token), data);
    }
}
