# Security Contracts

A collection of security-focused smart contracts for access control and governance operations.

## Components

### Access Control
- **Ownable**: Single owner with direct and two-step (start/accept/cancel) transfers; proxy-friendly
- **AccessControl**: Enumerated role-based permissions for granular function gating
- **PauserControl**: Lightweight circuit breaker

### Governance Council
- **GovernanceCouncil**: Weighted council governance with quorum/fast‑pass dual thresholds
- **Proposal Forwarders**: Plug‑in helpers that build calldata and emit typed events for proposal creation

    *See [src/governance/README.md](src/governance/README.md) for GovernanceCouncil architecture and mechanics.*

### Simple Council
- **SimpleCouncil**: Minimal equal‑weight council for external calls (immutable voters and params)
- **SimpleAdminCouncil**: SimpleCouncil + typed helpers for Ownable, AccessControl, and ProxyAdmin ops

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
    ├── simple-council/           # Minimal equal‑weight council variants
    │   ├── SimpleCouncil.sol       # Immutable voters + params
    │   └── SimpleAdminCouncil.sol  # SimpleCouncil + admin propose helpers
    └── proposal-forwarders/      # Proposal forwarder contracts
```