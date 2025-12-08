+++
title = "NXP-5: Account Providers"
date = "2025-12-08"
weight = 5
slug = "nxp-5-account-providers"
description = "Abstraction layer for account providers, enabling Nexum to manage accounts from diverse sources including native derivation, external EOA delegation, multisig membership, threshold signatures (FROST), smart contract accounts, and privacy protocols"

[taxonomies]
tags=["specification", "accounts", "delegation", "EIP-7702", "multisig", "FROST", "WebAuthn", "privacy", "NXP"]

[extra]
author = "mfw78"
+++

## Abstract

This specification (NXP-5) defines the account provider abstraction layer for Nexum, enabling unified management of accounts from diverse sources under a single identity. It establishes:

1. **Account Provider Interface**: Abstract interface for account sources
2. **Account Source Types**: Native, delegated, multisig, threshold, smart contract, and privacy-preserving accounts
3. **Provider Registration**: How account providers are registered and discovered
4. **Migration Workflows**: Bringing existing accounts under Nexum management

The core Nexum identity model remains rooted in BIP-32 hierarchical deterministic wallets, but this specification enables integration with any account source that can produce valid signatures or authorize transactions.

## Motivation

### Beyond Keys: The Account Abstraction

While [NXP-1](/specs/nxp-1-identity-model) through [NXP-4](/specs/nxp-4-storage-architecture) define Nexum's core identity and storage model around BIP-32 derived keys, real-world usage encompasses far more account types:

| Account Type | Key Relationship | Example |
|--------------|------------------|---------|
| Native EOA | Direct key ownership | BIP-44 derived account |
| Delegated EOA | EIP-7702 delegation | MetaMask account delegating to Nexum |
| Multisig | Signer membership | Safe owner |
| Threshold | Share holder | FROST participant |
| Smart Contract | Authorized signer | secp256r1 account (WebAuthn) |
| Privacy | Shielded key | Railgun, Aztec |

The common thread is not "key ownership" but "account control"—the ability to authorize actions on behalf of an address.

### Design Philosophy

NXP-5 abstracts at the **account** level, not the key level:

- An "account" is an address that can authorize transactions
- An "account provider" is any mechanism that enables authorization
- Providers are implementation-specific and extensible
- The interface is minimal: sign, authorize, verify

This allows Nexum to:
- Integrate with any current or future account type
- Support multiple authorization mechanisms per account
- Remain agnostic to specific cryptographic schemes
- Enable privacy-preserving accounts without special handling

## Specification

### 1. Account Provider Abstraction

#### 1.1 Core Interface

Account providers implement a minimal interface for account operations:

```rust
/// Account provider interface
///
/// Implementations provide account-specific signing and authorization.
/// The interface is intentionally minimal to support diverse account types.
trait AccountProvider {
    /// Unique identifier for this provider type
    fn provider_type(&self) -> &str;

    /// The account address (may be derived, computed, or external)
    fn address(&self) -> Address;

    /// Sign arbitrary message data
    /// Returns provider-specific signature format
    fn sign(&self, message: &[u8]) -> Result<Signature, ProviderError>;

    /// Sign typed data (EIP-712)
    fn sign_typed_data(&self, typed_data: &TypedData) -> Result<Signature, ProviderError>;

    /// Authorize a transaction
    /// May return a signature, UserOperation, or provider-specific authorization
    fn authorize_transaction(&self, tx: &Transaction) -> Result<Authorization, ProviderError>;

    /// Provider capabilities
    fn capabilities(&self) -> ProviderCapabilities;
}

/// What operations this provider supports
struct ProviderCapabilities {
    /// Can sign arbitrary messages
    can_sign_messages: bool,
    /// Can sign EIP-712 typed data
    can_sign_typed_data: bool,
    /// Can authorize transactions directly
    can_authorize_transactions: bool,
    /// Requires external interaction (hardware, network, user)
    requires_interaction: bool,
    /// Supports batch operations
    supports_batching: bool,
}
```

#### 1.2 Authorization Types

Different providers return different authorization formats:

```rust
/// Authorization result from a provider
enum Authorization {
    /// Standard ECDSA signature (secp256k1)
    EcdsaSignature(EcdsaSignature),

    /// ERC-4337 UserOperation (for smart contract accounts)
    UserOperation(UserOperation),

    /// EIP-7702 delegated authorization
    DelegatedAuth {
        delegate_signature: EcdsaSignature,
        delegation_proof: DelegationProof,
    },

    /// Threshold signature (aggregated from shares)
    ThresholdSignature(ThresholdSignature),

    /// Provider-specific authorization (for extensibility)
    Custom {
        provider_type: String,
        data: Vec<u8>,
    },
}
```

### 2. Account Source Types

#### 2.1 Native Accounts

Accounts derived directly from the Nexum seed via BIP-44:

```
Provider Type: "native"
Address: Derived from m/44'/60'/identity'/0/index
Authorization: Direct ECDSA signature
```

Native accounts are the foundation—they require no external dependencies and are fully recoverable from the seed phrase.

#### 2.2 Delegated Accounts (EIP-7702)

External EOAs that have delegated authority to a Nexum-derived key:

```
Provider Type: "delegated"
Address: External EOA address (provider-determined)
Authorization: Signature from delegation key + delegation proof
```

**Address ownership**: The provider determines the account address (the external EOA). This address is stored as `account_id` in [NXP-3](/specs/nxp-3-metadata-schema).

**Delegation key derivation**: When a Nexum-derived key is needed for control, it is derived from the account's address using the delegation key derivation method in [NXP-2 Section 3](/specs/nxp-2-derivation-path-standards#3-delegation-keys-identity-scoped-zero-metadata-discovery):

```
delegation_key = derive_from_address(identity, account_address)
```

**Key insight**: The external private key may optionally be imported and stored encrypted, but this is not required. The account is controlled via the delegation relationship.

#### 2.3 Multisig Membership

Accounts where the user is one of multiple signers:

```
Provider Type: "multisig"
Address: Multisig contract address (e.g., Safe)
Authorization: Signature contributing to threshold
```

The user may be a signer via:
- Native Nexum account (BIP-44 derived)
- Delegated account
- Any other account provider

Nexum tracks the membership relationship, not the multisig itself.

#### 2.4 Threshold Signatures (FROST, etc.)

Accounts controlled via threshold signature schemes:

```
Provider Type: "threshold"
Address: Derived from aggregate public key
Authorization: Partial signature (combined externally)
```

The user holds a key share, not the complete key. Signing requires coordination with other share holders.

#### 2.5 Smart Contract Accounts

Accounts implemented as smart contracts with custom validation:

```
Provider Type: "smart_contract"
Address: Contract address
Authorization: ERC-4337 UserOperation
```

Examples:
- **secp256r1 accounts**: WebAuthn/passkey authentication
- **Social recovery**: Guardian-based recovery
- **Session keys**: Time-limited delegated authority

#### 2.6 Privacy-Preserving Accounts

Shielded accounts from privacy protocols:

```
Provider Type: "shielded"
Address: Shielded address or viewing key
Authorization: Protocol-specific (e.g., Railgun proof)
```

These accounts may have:
- Different address formats
- Non-standard transaction flows
- Privacy-specific metadata requirements

### 3. Provider Registration

#### 3.1 Integration with NXP-3 Schema

[NXP-3](/specs/nxp-3-metadata-schema) defines the account registry with a discriminator between native and provider-managed accounts:

```proto
// From NXP-3: Account entry with oneof discriminator (messages for extensibility)
message AccountEntry {
  oneof account {
    NativeAccount native = 1;
    ProviderAccount provider = 2;
  }
  // ... other fields
}

message NativeAccount {
  uint32 index = 1;               // BIP-44 address_index: m/44'/60'/identity'/0/index
}

message ProviderAccount {
  bytes address = 1;              // 20-byte account address (provider-determined)
  string provider_type = 2;       // Provider type identifier (e.g., "delegated", "multisig")
  bytes provider_config = 3;      // Serialized provider-specific config (defined below)
}
```

For native accounts, no provider configuration is needed—the account is fully determined by its `NativeAccount.index` in the BIP-44 derivation path.

For provider accounts, the `ProviderAccount.provider_config` field contains the serialized configuration specific to that `provider_type`, as defined below.

#### 3.2 Provider Implementation Model

Providers are designed as pluggable modules implementing the `AccountProvider` trait (Section 1.1). This enables:

- **Modularity**: New providers can be added without schema changes
- **Isolation**: Each provider manages its own configuration format
- **Extensibility**: Future providers (e.g., WASM-based Safe module) can be integrated

```
┌─────────────────────────────────────────────────────────────────┐
│                    Account Provider Architecture                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   AccountRegistry (NXP-3)                                       │
│   ├── Native (account_id = index bytes)  → BIP-44 derivation    │
│   ├── Native (account_id = index bytes)  → BIP-44 derivation    │
│   ├── Provider (account_id = 0xabc...)   → DelegatedProvider    │
│   ├── Provider (account_id = 0xdef...)   → MultisigProvider     │
│   └── Provider (account_id = 0x123...)   → ThresholdProvider    │
│                                                                 │
│   Provider implementations (pluggable):                         │
│   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│   │ Delegated   │ │ Multisig    │ │ Threshold   │  ...          │
│   │ Provider    │ │ Provider    │ │ Provider    │               │
│   │ (builtin)   │ │ (builtin)   │ │ (WASM?)     │               │
│   └─────────────┘ └─────────────┘ └─────────────┘               │
│                                                                 │
│   For provider accounts requiring Nexum-derived control keys:   │
│   delegation_key = derive_from_address(identity, account_id)    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 3.3 Provider-Specific Configuration

Each provider type defines its own configuration schema. The `provider_type` string determines which schema applies:

```proto
// Delegated account (EIP-7702)
// provider_type = "delegated"
message DelegatedProviderConfig {
  bytes original_address = 1;             // The delegating EOA
  bytes delegation_signature = 2;         // EIP-7702 authorization signature
  repeated uint32 chain_ids = 3;          // Chains where delegation is active
  DelegationStatus delegation_status = 4;

  // Optional: imported key material (encrypted reference)
  optional bytes managed_key_ref = 5;
}

enum DelegationStatus {
  DELEGATION_STATUS_UNSPECIFIED = 0;
  DELEGATION_STATUS_PENDING = 1;          // Signed but not on-chain
  DELEGATION_STATUS_ACTIVE = 2;           // Confirmed on-chain
  DELEGATION_STATUS_REVOKED = 3;          // No longer valid
}

// Multisig membership
// provider_type = "multisig"
message MultisigProviderConfig {
  bytes multisig_address = 1;             // The multisig contract
  string multisig_type = 2;               // "safe", "gnosis", etc.
  uint32 signer_account_index = 3;        // Which Nexum account is the signer
  uint32 threshold = 4;                   // Required signatures
  uint32 total_signers = 5;               // Total signer count
}

// Threshold signature share
// provider_type = "threshold"
message ThresholdProviderConfig {
  string scheme = 1;                      // "frost", "gg20", etc.
  bytes group_public_key = 2;             // Aggregate public key
  uint32 share_index = 3;                 // This user's share index
  uint32 threshold = 4;                   // Required shares
  uint32 total_shares = 5;
  bytes encrypted_share = 6;              // Encrypted key share (if stored)
}

// Smart contract account
// provider_type = "smart_contract"
message SmartContractProviderConfig {
  bytes contract_address = 1;
  string account_type = 2;                // "erc4337", "safe", "kernel", etc.
  bytes init_code = 3;                    // For counterfactual addresses
  uint32 signer_account_index = 4;        // Which Nexum account authorizes
  string signature_type = 5;              // "secp256k1", "secp256r1", "ed25519"
}

// Shielded/privacy account
// provider_type = "shielded"
message ShieldedProviderConfig {
  string protocol = 1;                    // "railgun", "aztec", etc.
  bytes shielded_address = 2;
  bytes viewing_key = 3;                  // Encrypted
  bytes spending_key_ref = 4;             // Reference to encrypted spending key
}
```

### 4. Migration Workflows

#### 4.1 Delegation Migration (EIP-7702)

Bringing an external EOA under Nexum management via delegation:

```
┌──────────────────────────────────────────────────────────────────────┐
│                     EIP-7702 Delegation Migration                    │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. User connects external wallet                                    │
│     └── Nexum receives: external_address                             │
│                                                                      │
│  2. Nexum derives delegation key for (identity, external_address)    │
│     └── Path: m/44'/60'/identity'/1/addr[0]'/addr[1]'/...           │
│                                                                      │
│  3. User signs EIP-7702 authorization with external wallet           │
│     └── auth = { delegate: smart_contract_address, nonce, ... }      │
│     └── signature = external_wallet.sign(auth)                       │
│                                                                      │
│  4. Account added to registry with status = PENDING                  │
│                                                                      │
│  5. Authorization submitted on-chain                                 │
│     └── Option A: User broadcasts via external wallet                │
│     └── Option B: Bundled via ERC-4337 (gas tank pays)               │
│                                                                      │
│  6. On confirmation, status updated to ACTIVE                        │
│                                                                      │
│  7. Optional: Import external private key (encrypted storage)        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

#### 4.2 Multisig Onboarding

Adding a multisig where the user is already a signer:

```
┌─────────────────────────────────────────┐
│         Multisig Onboarding             │
├─────────────────────────────────────────┤
│ 1. User provides multisig address       │
│ 2. Nexum queries on-chain for signers   │
│ 3. User identifies which signer is      │
│    controlled by this identity          │
│ 4. Account added with MultisigProvider  │
│                                         │
│ Signing: Contributes signature to       │
│          multisig transaction flow      │
└─────────────────────────────────────────┘
```

#### 4.3 Threshold Share Import

Joining a threshold signature group:

```
┌─────────────────────────────────────────┐
│         Threshold Share Import          │
├─────────────────────────────────────────┤
│ 1. User receives share from DKG or      │
│    trusted dealer                       │
│ 2. Share encrypted with identity        │
│    storage key                          │
│ 3. Account added with group public key  │
│    as the address                       │
│                                         │
│ Signing: Partial signature generated    │
│          locally, combined externally   │
└─────────────────────────────────────────┘
```

#### 4.4 Smart Contract Account Setup

Creating or importing a smart contract account:

```
┌─────────────────────────────────────────┐
│      Smart Contract Account Setup       │
├─────────────────────────────────────────┤
│ 1. Option A: Deploy new account         │
│    - Generate init code                 │
│    - Compute counterfactual address     │
│    - Deploy on first transaction        │
│                                         │
│ 2. Option B: Import existing            │
│    - Provide contract address           │
│    - Verify signer authorization        │
│                                         │
│ Signing: Via ERC-4337 UserOperation     │
└─────────────────────────────────────────┘
```

### 5. Provider Discovery

#### 5.1 On-Chain Discovery

Some provider relationships are discoverable on-chain:

| Provider Type | Discovery Method |
|---------------|------------------|
| Delegated | Check EIP-7702 delegation at address |
| Multisig | Query signer list from contract |
| Smart Contract | Check authorized signers |

#### 5.2 Metadata-Based Discovery

Other relationships require stored metadata:

| Provider Type | Discovery Method |
|---------------|------------------|
| Native | Derive from seed + identity index |
| Threshold | Requires stored share + group info |
| Shielded | Requires stored viewing/spending keys |

### 6. Security Considerations

#### 6.1 Provider Trust Model

| Provider Type | Trust Assumption |
|---------------|------------------|
| Native | Seed security only |
| Delegated | Seed + delegation key security |
| Multisig | Seed + other signers' honesty |
| Threshold | Seed + threshold of honest participants |
| Smart Contract | Seed + contract correctness |
| Shielded | Seed + protocol security |

#### 6.2 Key Material Protection

When providers store key material (shares, imported keys):

1. **Encryption at rest**: Always encrypted with identity storage key
2. **Memory protection**: Clear from memory after use
3. **Secure deletion**: Cryptographic wipe when removed
4. **Audit logging**: Track access to sensitive material

#### 6.3 Delegation Security

For EIP-7702 delegated accounts:

| Risk | Mitigation |
|------|------------|
| Delegation key compromise | Revoke delegation on-chain |
| Unauthorized delegation | Require explicit user confirmation |
| Stale delegation status | Periodic on-chain verification |

### 7. Implementation Requirements

#### 7.1 MUST

1. Implement AccountProvider interface for all account types
2. Store provider configuration in account registry
3. Encrypt any stored key material with identity storage key
4. Support native accounts (BIP-44 derived)
5. Validate provider state before signing operations

#### 7.2 SHOULD

1. Support EIP-7702 delegated accounts
2. Support ERC-4337 smart contract accounts
3. Provide on-chain discovery for supported provider types
4. Implement provider status monitoring (revocation detection)

#### 7.3 MAY

1. Support multisig membership tracking
2. Support threshold signature schemes
3. Support privacy protocol integration
4. Implement provider-specific UIs

## References

- [NXP-1: Identity Model](/specs/nxp-1-identity-model)
- [NXP-2: Derivation Path Standards](/specs/nxp-2-derivation-path-standards)
- [NXP-3: Metadata Schema](/specs/nxp-3-metadata-schema)
- [NXP-4: Storage Architecture](/specs/nxp-4-storage-architecture)
- [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry)
- [EIP-7702: Set EOA account code](https://eips.ethereum.org/EIPS/eip-7702)
- [ERC-4337: Account Abstraction](https://eips.ethereum.org/EIPS/eip-4337)
- [FROST: Flexible Round-Optimized Schnorr Threshold Signatures](https://eprint.iacr.org/2020/852)
- [WebAuthn Specification](https://www.w3.org/TR/webauthn-2/)
- [Railgun Protocol](https://railgun.org/)

## Changelog

### Version 1.0.0 (2025-12-08)

- Initial NXP-5 specification
- Define account provider abstraction layer
- Specify account source types (native, delegated, multisig, threshold, smart contract, shielded)
- Document provider registration and configuration schemas
- Define migration workflows for various account types
- Establish security requirements for provider implementations

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
