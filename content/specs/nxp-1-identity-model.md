+++
title = "NXP-1: Identity Model"
date = "2025-12-07"
weight = 1
slug = "nxp-1-identity-model"
description = "Foundational identity model for Nexum, establishing how identities map to BIP-44 derivation paths, the one-to-many relationship between identities and accounts, strict identity isolation requirements, system account allocations, connection binding, and EIP-7702 delegation-based recovery"

[taxonomies]
tags=["specification", "identity", "account", "BIP44", "EIP-7702", "delegation", "recovery", "NXP"]

[extra]
author = "mfw78"
+++

## Abstract

This specification (NXP-1) defines the foundational identity model for Nexum. It establishes how identities map to BIP-44 derivation paths, the one-to-many relationship between identities and accounts, identity isolation requirements, and the identity lifecycle.

NXP-1 serves as the foundation for subsequent specifications that define derivation paths, metadata schemas, and storage architecture.

## Motivation

Nexum requires a coherent identity model that:

1. **Aligns with BIP-44**: The `account'` level in derivation paths naturally represents an "identity"
2. **Supports multiple accounts per identity**: The `address_index` level provides one-to-many account relationship
3. **Guarantees identity isolation**: Identities MUST remain strictly separated to prevent cross-bleed and linking
4. **Enables system accounts**: Reserved indices for infrastructure operations (e.g., gas tanks for account abstraction)
5. **Provides identity-scoped configuration**: Preferences and settings apply to an identity as a whole

## Specification

### 1. Identity Definition

An **identity** in Nexum corresponds directly to the hardened `account'` level in the BIP-44 derivation path:

```
m / 44' / 60' / identity' / change / address_index
```

Where:
- `44'` — BIP-44 purpose (hardened)
- `60'` — Ethereum coin type (hardened)
- `identity'` — Identity index (hardened), providing cryptographic isolation
- `change` — External chain (`0` for receive addresses)
- `address_index` — Account index within the identity

Each unique value of `identity'` represents a completely separate identity with:
- Independent cryptographic material (hardened derivation)
- Independent metadata and preferences
- Independent account namespace
- No possibility of cross-identity key derivation

### 2. Identity-Account Relationship

#### 2.1 One-to-Many Model

Each identity contains multiple accounts through the `address_index` derivation level:

```
Identity 0 (m/44'/60'/0'/0/*)
├── Account 0: m/44'/60'/0'/0/0
├── Account 1: m/44'/60'/0'/0/1
├── Account 2: m/44'/60'/0'/0/2
└── ...

Identity 1 (m/44'/60'/1'/0/*)
├── Account 0: m/44'/60'/1'/0/0
├── Account 1: m/44'/60'/1'/0/1
└── ...
```

This provides:
- **Identity isolation**: Different `identity'` indices cannot derive each other's keys
- **Account multiplicity**: Unlimited accounts per identity via `address_index`
- **BIP-44 compliance**: Standard derivation path semantics

#### 2.2 Account Types

Accounts within an identity are partitioned into user and system regions. See [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry) for index space partitioning details.

**User accounts**:
- Controlled by the user
- Organized via metadata labels
- Used for general signing operations

**System accounts**:
- Reserved for Nexum infrastructure
- Use indices in the system range as defined in [Appendix I](/specs/appendix-i-system-key-registry)
- Include the **gas tank** for account abstraction scenarios:
  - Holds funds for paying gas on behalf of other accounts in the identity
  - Enables gasless UX for user accounts via paymasters or relayers
  - Is identity-scoped (each identity has its own gas tank)
  - See [Appendix I §2.2](/specs/appendix-i-system-key-registry#22-signing-key-registry) for the specific index allocation

### 3. Identity Isolation

#### 3.1 Requirements

Identities MUST be strictly isolated:

1. **Cryptographic isolation**: Hardened derivation at the `identity'` level prevents any key relationship between identities
2. **Metadata isolation**: Each identity maintains completely separate metadata stores
3. **Preference isolation**: Configuration and settings are identity-scoped
4. **UI isolation**: Wallet interfaces SHOULD present identities as entirely separate entities

#### 3.2 Rationale

Strict isolation prevents:
- **Privacy leakage**: No linking of accounts across identities via key derivation
- **Metadata correlation**: No shared labels, folders, or organizational data
- **Configuration bleed**: No shared preferences or settings
- **UX confusion**: Clear separation in user interfaces

### 4. Identity Lifecycle

#### 4.1 Creation

An identity is **implicitly created** when:
1. A new `identity'` index is used for key derivation
2. Metadata is stored for that identity

There is no explicit "create identity" operation—using a new index creates the identity.

#### 4.2 Enumeration

Identities are enumerated via **deterministic metadata location**:

1. Each identity stores its metadata at a deterministic location derived from the identity index
2. Enumeration iterates through identity indices (0, 1, 2, ...) and retrieves metadata from each location
3. An identity exists if metadata is present at its deterministic location

```
Identity 0 → metadata at deterministic_location(0)
Identity 1 → metadata at deterministic_location(1)
Identity 2 → metadata at deterministic_location(2)
...
```

**Optional fallback**: Implementations MAY additionally support BIP-44 gap-limit scanning (20 consecutive empty accounts) for recovery scenarios where metadata is unavailable.

#### 4.3 Switching

Switching between identities:
1. **Terminate all connections**: Close all backend connections, streams, and subscriptions bound to the current identity
2. Unload current identity's metadata and state
3. Load target identity's metadata and state
4. Establish new connections bound to the target identity
5. Update UI to reflect new identity context

Active identity MUST be clearly indicated to the user.

#### 4.4 Connection Binding

All backend connections and streams MUST be identity-scoped to prevent cross-identity data leakage:

```
Identity N
├── Connection to Backend A (identity-bound)
│   ├── Stream for Account 0
│   ├── Stream for Account 1
│   └── Stream for Account 2
└── Connection to Backend B (identity-bound)
    └── Stream for Account 0
```

**Requirements:**
- Connections to backends (RPC nodes, indexers, etc.) MUST be established per-identity
- Sub-streams within a connection MAY be bound to specific accounts
- On identity switch, ALL connections for the previous identity MUST be terminated
- Connections MUST NOT be reused across identities
- Connection metadata (auth tokens, session IDs) MUST NOT leak between identities

#### 4.5 Deletion

Identity deletion is a **metadata-only operation**:
1. Delete identity's stored metadata
2. Clear identity's preferences
3. Remove from identity list

**Important**: Deletion does NOT:
- Destroy the underlying keys (they can always be re-derived from seed)
- Move funds (user is responsible for transferring assets first)
- Affect other identities

### 5. Account Recovery

#### 5.1 Preferred Method: EIP-7702 Delegation

The preferred recovery mechanism is via [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) delegation to externally-secured accounts:

- **Multisig**: Traditional multi-signature wallets (e.g., Safe)
- **MPC**: Multi-party computation key shares
- **FROST**: Flexible Round-Optimized Schnorr Threshold signatures
- **Similar schemes**: Any threshold or distributed signing mechanism

Delegation allows a secured external account to act on behalf of any account within an identity, providing recovery without seed phrase exposure.

#### 5.2 Delegation Isolation

To maintain identity isolation, delegation MUST follow these rules:

1. **No shared delegates**: Two identities MUST NOT delegate to the same external account
2. **Per-identity delegates**: Each identity SHOULD have its own dedicated delegate account(s)
3. **Rationale**: Sharing a delegate creates an obvious on-chain link between identities

```
Identity 0 → delegates to → Multisig A
Identity 1 → delegates to → Multisig B  (different from A)
```

#### 5.3 Optional: Seed Phrase Backup

Users MAY choose to backup their seed phrase as an additional recovery option. This is NOT required and carries risks:

- Seed compromise affects ALL identities simultaneously
- Physical backup security is user's responsibility

### 6. Identity Metadata

#### 6.1 No Cross-Identity Organization

Identities MUST NOT support folder/file structuring or any organizational metadata that spans multiple identities. Such metadata would implicitly link identities together, violating the isolation requirement.

**Prohibited:**
- Folder structures containing multiple identities
- Tags or labels shared across identities
- Any metadata that references other identities

#### 6.2 Per-Identity Metadata

Each identity MAY have its own independent metadata (name, avatar, preferences), but this metadata:

1. **MUST** be stored separately per-identity
2. **MUST NOT** reference other identities
3. **MUST** be encrypted at rest
4. **MAY** be extensible for implementation-specific fields

Folder/file organizational metadata applies only to **accounts within an identity**, not to identities themselves.

### 7. Security Considerations

#### 7.1 Identity Correlation

While identities are cryptographically isolated, correlation is still possible via:
- On-chain transaction patterns
- Timing analysis
- Shared EIP-7702 delegates (violates Section 5.2)
- Metadata leakage (if storage is compromised)

Users seeking maximum privacy SHOULD:
- Use different funding sources for different identities
- Use separate delegate accounts per identity
- Avoid patterns that link identities temporally or behaviorally

#### 7.2 Seed Phrase Risks

If a user chooses to backup their seed phrase:
- Seed compromise affects ALL identities simultaneously
- All accounts across all identities become vulnerable

### 8. Implementation Requirements

#### 8.1 MUST

1. Use hardened derivation for the identity (`account'`) level
2. Maintain strict metadata separation between identities
3. Support identity enumeration via deterministic metadata location
4. Clearly indicate active identity in UI
5. Enforce delegation isolation (no shared delegates across identities)
6. Terminate all identity-bound connections on identity switch
7. Bind all backend connections and streams to a specific identity

#### 8.2 SHOULD

1. Support multiple identities simultaneously loaded
2. Provide identity switching UX
3. Reserve system account index for gas tank
4. Support EIP-7702 delegation setup for recovery

#### 8.3 MAY

1. Support identity naming and avatars
2. Implement identity-scoped preferences
3. Support optional seed phrase backup
4. Support BIP-44 gap-limit scanning as fallback recovery

## References

- [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry)
- [BIP-44: Multi-Account Hierarchy](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki)
- [EIP-7702: Set EOA account code](https://eips.ethereum.org/EIPS/eip-7702)
- [GitHub Issue #84](https://github.com/nxm-rs/nexum/issues/84)

## Changelog

### Version 1.0.0 (2025-12-07)

- Initial NXP-1 specification
- Define identity as BIP-44 account' level
- Specify identity-account one-to-many relationship
- Document identity isolation requirements
- Define system accounts including gas tank
- Describe identity lifecycle operations (creation, enumeration, switching, deletion)
- Specify deterministic metadata location for identity enumeration
- Specify EIP-7702 delegation as preferred recovery mechanism
- Document delegation isolation requirements
- Define connection binding requirements for identity isolation

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
