# Governance Council System

Weighted multi-sig governance with dual thresholds and pluggable proposal forwarders.

## Overview

The contracts implement a simple trust model where council members (voters) can propose and vote on protocol operations. The system features dual thresholds for different security levels and supports extensible proposal forwarders for convenient governance workflows.

## Core Components

### 1. GovernanceCouncil

The main governance contract with these features:

- Weighted voting
- Multiple proposal types
- Dual thresholds (quorum / fast-pass) with auto fast-pass detection
- Reentrancy, deadline, and data-hash safeguards

#### Proposal Types

`External` | `ParamUpdate` | `VoterUpdate` | `ProposalForwarderUpdate` | `FastPassUpdate` | `TokenTransfer`

#### Dual Threshold System

Quorum (e.g. 60%) applies by default; fast-pass (e.g. 40%) applies to pre-authorized external functions, auto-detected at execution.

### 2. Proposal Forwarder

Trusted helper contracts that create proposals for users. Purely ergonomic: encode calldata, emit typed events, preserve the original caller.

- **Encode calldata** (`abi.encodeWithSelector()`)
- **Clear events** (decoded parameters for monitoring)
- **Type safety** (avoid manual encoding mistakes)

#### Available Abstract Forwarders

`AccessControlForwarder`: ownership + access role mamangements  
`ProxyAdminForwarder`: contract upgrades, proxy admin changes

**Example**: Instead of manually encode proposal calldata, call the forwarder's `proposeGrantRole(target, role, account)`, which handles encoding and emits `GrantRoleProposed(proposalId, target, role, account)`.

**Deployment Pattern**: Deploy a single aggregate immutable forwarder combining needed abstract modules; new capabilities later require deploying an additional forwarder.

## Security & Trust Model

### Trust Model

The system operates on a **simple trust model**:

1. **Voters**: Trusted council members who can create and vote on proposals
2. **Proposal Forwarders**: Audited, immutable; type-safe interfaces + decoded events; eliminate manual encoding
3. **Fast-Pass Authorization**: Pre‑authorized external calls with lower threshold

#### Core Trust Assumption

**Voters with sufficient power (meeting current quorum threshold) can do whatever they want.** This includes:

- Modifying governance parameters (thresholds, active periods) while other proposals are pending
- Changing voter powers or adding/removing voters during active proposal periods  
- Modifying fast-pass authorizations that affect threshold calculations for pending proposals
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
- **Fast-Pass Authorization**: Only authorize low-risk operations for fast-pass

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
council.executeProposal(proposalId, ProposalType.External, target, callData);
```

### Through Proposal Forwarders

Users can leverage forwarders for type-safe, error-resistant operations:

```solidity
// Instead of manually packing calldata, use the forwarder for safety and clarity:
AccessControlForwarder forwarder = AccessControlForwarder(forwarderAddress);
forwarder.proposeGrantRole(targetContract, role, account);

// Automatically emits: GrantRoleProposed(proposalId, targetContract, role, account)
```

### Fast-Pass Configuration

Configure operations for expedited processing:

```solidity
// Authorize function for fast-pass
address[] memory targets = [targetContract];
// Use selector bytes4(0) to wildcard all functions on a target
bytes4[] memory selectors = [MyContract.someFunction.selector];
bool[] memory authorized = [true];

council.proposeFastPassUpdate(targets, selectors, authorized);
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
    60,        // quorum threshold (60%)
    40         // fast-pass threshold (40%)
);
```

**Threshold Examples**: Quorum: 300/500 (60%) → 3 voters. Fast-pass: 200/500 (40%) → 2 voters. Practical: 3 regular, 2 fast-pass.

### For Protocol Teams

1. **Deploy Council**: Set up voters, powers, and initial forwarders
2. **Configure Fast-Pass**: Authorize routine operations for efficiency
3. **Create Custom Forwarders**: Build specialized forwarders for your protocol's needs
4. **Integrate Access Control**: Use governance for protocol parameter management

### For Forwarder Developers

1. **Inherit Base**: Extend `ProposalForwarderBase`
2. **Implement Interface**: Create user-friendly proposal creation functions
3. **Emit Events**: Include detailed events for transparency
4. **Security Review**: Ensure immutability and proper caller forwarding

## Testing

Comprehensive unit and integration tests (proposal lifecycle, edge cases, fast-pass logic).

See `/test/governance/README.md` for detailed test documentation.
