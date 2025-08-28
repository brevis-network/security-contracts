# Security Contracts

A collection of security-focused smart contracts for access control and governance operations.

## Components

### Access Control
- **Ownable**: Single owner supporting proxy-based upgrade patterns
- **AccessControl**: Enumerated role-based permissions for granular function gating
- **PauserControl**: Lightweight circuit breaker

### Governance Council
- **GovernanceCouncil**: Weighted council governance with quorum/fast‑pass dual thresholds
- **Proposal Forwarders**: Plug‑in helpers that build calldata and emit typed events for proposal creation

*See [src/governance/README.md](src/governance/README.md) for detailed architecture and mechanics.*

## Structure

```
src/
├── access/                     # Access control contracts
│   ├── AccessControl.sol         # Role-based access control
│   ├── Ownable.sol               # Simple ownership management
│   ├── PauserControl.sol         # Emergency pause functionality
│   └── interfaces/               # Access control interfaces
│
└── governance/                 # Governance system contracts
    ├── GovernanceCouncil.sol     # Multisig governance contract
    ├── IGovernanceCouncil.sol    # Governance council interface
    └── proposal-forwarders/      # Proposal forwarder contracts
```