# Security Contracts

A collection of security-focused smart contracts for access control and governance operations.

## Components

### Access Control
- **AccessControl**: Role-based permissions with enumerable role management
- **Ownable**: Single-owner contracts with ownership transfer capability  
- **PauserControl**: Emergency pause mechanism for contract operations

### Governance Council
- **GovernanceCouncil**: Weighted multi-signature voting with dual thresholds (quorum and fast-pass). Features a simple trust model where council members can propose and vote on critical protocol operations.
- **Proposal Forwarder**: Extensible architecture with trusted proposal forwarder contracts that can create proposals on behalf of voters, enabling flexible and convenient governance workflows.

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
    ├── GovernanceCouncil.sol     # Multi-signature governance contract
    ├── IGovernanceCouncil.sol    # Governance council interface
    └── proposal-forwarders/      # Proposal forwarder contracts
```