# Governance Council System

Weighted multi-sig governance with a quorum threshold and pluggable proposal forwarders.

## Overview

The contracts implement a simple trust model where council members (voters) can propose and vote on protocol operations. The system features a single quorum threshold and supports extensible proposal forwarders for convenient governance workflows.

> Note: For a minimal, equal‑weight alternative with immutable voters and parameters, see [SimpleCouncil](./simple-council/SimpleCouncil.sol) and [SimpleAdminCouncil](./simple-council/SimpleAdminCouncil.sol).

## Core Components

### 1. GovernanceCouncil

The main governance contract with these features:

- Weighted voting
- Multiple proposal types
- Single quorum threshold
- Reentrancy, deadline, and data-hash safeguards

#### Quorum Threshold

A single quorum threshold (e.g. 60%) applies to all proposals.

### 2. Proposal Forwarder

Trusted helper contracts that create proposals for users. Purely ergonomic: encode calldata, emit typed events, preserve the original caller.

- **Encode calldata** (`abi.encodeWithSelector()`)
- **Clear events** (decoded parameters for monitoring)
- **Type safety** (avoid manual encoding mistakes)

#### Available Abstract Forwarders

`AccessControlForwarder`: ownership + access role management
`ProxyAdminForwarder`: contract upgrades, proxy admin changes

**Example**: Instead of manually encoding proposal calldata, call the forwarder's `proposeGrantRole(target, role, account)`, which handles encoding and emits `GrantRoleProposed(proposalId, target, role, account)`.

**Deployment Pattern**: Deploy a single aggregate immutable forwarder combining needed abstract modules; new capabilities later require deploying an additional forwarder.

## Security & Trust Model

### Trust Model

The system operates on a **simple trust model**:

1. **Voters**: Trusted council members who can create and vote on proposals
2. **Proposal Forwarders**: Audited, immutable; type-safe interfaces + decoded events; eliminate manual encoding
3. **Proposal Forwarders**: Optional convenience layer; doesn’t change required quorum

#### Core Trust Assumption

**Voters with sufficient power (meeting current quorum threshold) can do whatever they want.** This includes:

- Modifying governance parameters (quorum threshold, active period) while other proposals are pending
- Changing voter powers or adding/removing voters during active proposal periods  
- Any other governance action at any time

**Race Conditions by Design**: Configuration changes during pending proposals are intentional, not bugs. If voters can execute a proposal to change parameters, they already have enough power to execute any other proposal under either the old or new parameters.

### Security Principles

1. **Data Integrity**: All proposals include cryptographic hashes to prevent tampering
2. **Reentrancy Protection**: Built-in protection against reentrancy attacks
3. **Deadline Enforcement**: All proposals have expiration times to prevent stale executions
4. **Immutable Forwarders**: Proposal forwarders must be non-upgradable to prevent trust issues
5. **Transparent Forwarding**: Forwarders must pass through the original caller as the proposer

#### Operational Requirements

- **Secure Keys & Review**: Secure voter keys; review proposals before execution
- **Threshold Configuration**: Set thresholds appropriate for your security model
 

## Usage and Integration

### Direct Governance

Voters can directly create proposals:

```solidity
// Encoded function call data bytes for target contract
bytes memory callData = /* abi.encodeWithSelector(...) */;

// Create external proposal
uint256 proposalId = council.createProposal(target, callData);

// Vote on proposal
council.voteProposal(proposalId, true);

// Execute when threshold met
council.executeProposal(proposalId, target, callData);
```

### Through Proposal Forwarders

Users can leverage forwarders for type-safe, error-resistant operations:

```solidity
// Instead of manually packing calldata, use the forwarder for safety and clarity:
AccessControlForwarder forwarder = AccessControlForwarder(forwarderAddress);
forwarder.proposeGrantRole(targetContract, role, account);

// Automatically emits: GrantRoleProposed(proposalId, targetContract, role, account)
```

 

### Initial Setup

```solidity
address[] memory voters = [voter1, voter2, voter3, voter4, voter5];
uint256[] memory powers = [100, 100, 100, 100, 100]; // Total: 500
address[] memory forwarders = [governanceForwarder]; // Single contract with multiple forwarder capabilities

GovernanceCouncil council = new GovernanceCouncil(
    voters,
    powers, 
    forwarders,
    7 days,    // active period
    60         // quorum threshold (60%)
);
```

**Threshold Example**: Quorum: 300/500 (60%) → typically 3 voters of equal power.

### For Protocol Teams

1. **Deploy Council**: Set up voters, powers, and initial forwarders
2. **Create Custom Forwarders**: Build specialized forwarders for your protocol's needs
3. **Integrate Access Control**: Use governance for protocol parameter management

### For Forwarder Developers

1. **Inherit Base**: Extend `ProposalForwarderBase`
2. **Implement Interface**: Create user-friendly proposal creation functions
3. **Emit Events**: Include detailed events for transparency
4. **Security Review**: Ensure immutability and proper caller forwarding

## Testing

Comprehensive unit and integration tests (proposal lifecycle and edge cases).

See `/test/governance/README.md` for detailed test documentation.
