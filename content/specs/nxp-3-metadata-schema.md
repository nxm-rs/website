+++
title = "NXP-3: Metadata Schema"
date = "2025-12-08"
weight = 3
slug = "nxp-3-metadata-schema"
description = "Metadata schema specification for Nexum, defining data structures for identities, accounts, preferences, and signature audit trail with versioning and migration support"

[taxonomies]
tags=["specification", "metadata", "schema", "protobuf", "versioning", "NXP"]

[extra]
author = "mfw78"
+++

## Abstract

This specification (NXP-3) defines the metadata schema for Nexum. It establishes data structures for identities, accounts, preferences, and signature audit trails, along with versioning strategies and migration procedures.

NXP-3 builds on [NXP-1 (Identity Model)](/specs/nxp-1-identity-model) which defines the entities requiring schemas, and [NXP-2 (Derivation Path Standards)](/specs/nxp-2-derivation-path-standards) which defines key derivation paths.

## Motivation

Nexum requires well-defined metadata schemas that:

1. **Support versioning**: Schema evolution without breaking existing data
2. **Enable migration**: Clear procedures for upgrading between versions
3. **Maintain isolation**: Identity-scoped metadata with no cross-identity leakage
4. **Define boundaries**: Clear encryption boundaries for sensitive fields
5. **Optimize storage**: Minimize cascading updates when frequently-changed data is modified
6. **Enable efficient sync**: Separate high-churn data from stable metadata

## Specification

### 1. Serialization Format

All metadata uses Protocol Buffers (protobuf) for serialization:

- **Compact**: Binary format minimizes storage size
- **Versioned**: Built-in field numbering supports schema evolution
- **Typed**: Strong typing prevents data corruption
- **Cross-platform**: Wide language support for implementations

### 2. Storage-Aware Schema Design

#### 2.1 Design Principles

Metadata is organized into separate storage units based on update frequency:

| Storage Unit | Update Frequency | Contents |
|--------------|------------------|----------|
| Version Manifest | Rarely | Schema versions, storage locations |
| Identity Core | Infrequently | Identity info, preferences |
| Account Registry | Occasionally | Account list with references |
| Account Details | Per-account | Individual account metadata |
| Signature Audit | Per-account, continuously | Signature records (append-only, per account) |

This separation ensures that:
- Updating one account doesn't require rewriting all accounts
- High-frequency signature logging doesn't cascade to identity metadata
- Per-account signature logs enable O(1) lookup and append without affecting other accounts
- Schema migrations can be applied independently per storage unit

#### 2.2 Version Manifest

The version manifest is the root document for an identity, stored at the deterministic location defined in [NXP-1 Section 5.2](/specs/nxp-1-identity-model#52-enumeration). It tracks schema versions for all sub-entities and their storage locations.

```proto
syntax = "proto3";

package nexum.metadata;

// Root manifest for an identity's metadata
// Stored at deterministic location derived from identity index
message VersionManifest {
  uint32 manifest_version = 1;            // Manifest schema version

  // Schema versions for each sub-entity (similar to libp2p topic versioning)
  map<string, uint32> schema_versions = 2;
  // Keys: "identity_core", "account_registry", "account_details", "signature_audit"

  // Storage references for each sub-entity
  map<string, bytes> storage_refs = 3;    // Swarm references (64-byte encrypted refs)

  // Identity index (for verification)
  uint32 identity_index = 4;

  // Timestamps
  google.protobuf.Timestamp created = 5;
  google.protobuf.Timestamp updated = 6;
}
```

#### 2.3 Migration Procedures

When loading metadata:

1. Fetch version manifest from deterministic location
2. For each sub-entity:
   - Check `schema_versions[entity]` against current implementation version
   - If version mismatch, apply sequential migrations
   - Fetch from `storage_refs[entity]`, migrate, and re-store
3. Update manifest with new versions and storage refs

Implementations MUST support reading all previous schema versions for each sub-entity.

### 3. Identity Core

The identity core contains stable identity-level information and preferences. It is referenced from the version manifest.

#### 3.1 Schema Definition

```proto
// Identity core metadata
// Referenced from VersionManifest.storage_refs["identity_core"]
message IdentityCore {
  uint32 schema_version = 1;              // Current: 1

  // Identity information
  uint32 index = 2;                       // Identity index (account' in BIP-44)
  string name = 3;                        // Human-readable name (optional)
  bytes avatar_ref = 4;                   // Swarm reference to avatar image (64 bytes encrypted ref)
  string avatar_mime_type = 5;            // MIME type for avatar (e.g., "image/png")

  // Preferences
  IdentityPreferences preferences = 6;

  // Timestamps
  google.protobuf.Timestamp created = 7;
  google.protobuf.Timestamp updated = 8;

  // Note: No folder field - identities are not organized hierarchically
  // Per NXP-1 Section 7, cross-identity organization is prohibited
}
```

### 4. Account Metadata

Account metadata is split into two layers to optimize storage:

1. **Account Registry**: Lightweight index of all accounts with storage references
2. **Account Details**: Full metadata for individual accounts (stored separately)

This separation ensures that updating one account's details doesn't require rewriting the entire account list.

#### 4.1 Account Registry

The account registry is a lightweight index of all accounts within an identity.

```proto
// Account registry - lightweight index of accounts
// Referenced from VersionManifest.storage_refs["account_registry"]
message AccountRegistry {
  uint32 schema_version = 1;              // Current: 1
  repeated AccountEntry accounts = 2;
  google.protobuf.Timestamp updated = 3;
}

// Lightweight account entry (stored in registry)
message AccountEntry {
  // Account identification - type and identifier are coupled via oneof
  // Using messages allows future extensibility for each account type
  oneof account {
    NativeAccount native = 1;
    ProviderAccount provider = 2;
  }

  string label = 3;                       // Human-readable label (for quick display)
  bytes details_ref = 4;                  // Swarm reference to AccountDetails (64 bytes)
  bytes audit_ref = 5;                    // Swarm reference to SignatureAuditLog (64 bytes)
}

// Native account: BIP-44 derived from identity seed
message NativeAccount {
  uint32 index = 1;                       // BIP-44 address_index: m/44'/60'/identity'/0/index
  // Future fields can be added here without breaking compatibility
}

// Provider-managed account: controlled by an account provider (see NXP-5)
message ProviderAccount {
  bytes address = 1;                      // 20-byte account address (provider-determined)
  string provider_type = 2;               // Provider type identifier (e.g., "delegated", "multisig")
  bytes provider_config = 3;              // Serialized provider-specific config (see NXP-5)
}

// Note: For provider accounts that require a Nexum-derived key for control
// (e.g., EIP-7702 delegation), the delegation key is derived from the
// address using the method defined in NXP-2 Section 3.
```

#### 4.2 Account Details

Full account metadata stored separately for each account.

```proto
// Full account details - stored separately per account
// Referenced from AccountEntry.details_ref
message AccountDetails {
  uint32 schema_version = 1;              // Current: 1

  // Account identifier (must match AccountEntry.account oneof)
  oneof account {
    NativeAccount native = 2;
    ProviderAccount provider = 3;
  }

  // Organizational metadata
  string label = 4;                       // Human-readable label
  string folder = 5;                      // Organizational path (e.g., "/savings/cold")
  repeated string tags = 6;               // Searchable tags (identity-scoped only)
  string notes = 7;                       // Free-form notes (optional)
  bytes icon_ref = 8;                     // Swarm reference to custom icon (64 bytes encrypted ref)
  string icon_mime_type = 9;              // MIME type for icon

  // Categorization
  AccountCategory category = 10;

  // Account-specific preferences (override identity defaults)
  AccountPreferences preferences = 11;

  // Timestamps
  google.protobuf.Timestamp created = 12;
  google.protobuf.Timestamp updated = 13;

  // Fields 14-19 reserved for future use
  // Field 20+ reserved for extensions
}

enum AccountCategory {
  ACCOUNT_CATEGORY_UNSPECIFIED = 0;
  ACCOUNT_CATEGORY_DEFAULT = 1;           // General purpose
  ACCOUNT_CATEGORY_SAVINGS = 2;           // Long-term storage
  ACCOUNT_CATEGORY_TRADING = 3;           // Active trading
  ACCOUNT_CATEGORY_DEFI = 4;              // DeFi interactions
  ACCOUNT_CATEGORY_NFT = 5;               // NFT storage
  ACCOUNT_CATEGORY_BURNER = 6;            // Temporary/disposable
}
```

#### 4.3 Folder Structure

Folders provide hierarchical organization within an identity:

- Path separator: `/`
- Root: Empty string or `/`

**Example paths:**
```
/                       # Root (default)
/savings
/savings/cold-storage
/trading/dex
/nfts/art
```

### 5. Preferences

#### 5.1 Identity Preferences

```proto
// Identity-scoped preferences
message IdentityPreferences {
  // Display settings
  string default_currency = 1;            // Fiat currency code (e.g., "USD", "EUR")
  string locale = 2;                      // BCP 47 locale tag (e.g., "en-US")

  // Network preferences
  repeated uint32 enabled_chain_ids = 3;  // Enabled blockchain networks
  uint32 default_chain_id = 4;            // Default network for new operations

  // Privacy settings
  bool hide_balances = 5;                 // Hide balance display by default
  bool hide_small_balances = 6;           // Hide dust/small balances
  uint64 small_balance_threshold = 7;     // Threshold in wei for "small"

  // Transaction settings
  GasPreference gas_preference = 8;
  uint32 default_slippage_bps = 9;        // Default slippage in basis points

  // Notification preferences
  NotificationPreferences notifications = 10;

  // Audit trail preferences
  AuditPreferences audit = 11;
}

// Audit trail configuration
message AuditPreferences {
  // Keys excluded from audit trail (by system key identifier)
  // Example: ["swarm_batch_owner", "swarm_feed_owner"]
  repeated string excluded_system_keys = 1;

  // Whether to audit all signature types by default
  bool audit_all_signatures = 2;          // Default: true
}

enum GasPreference {
  GAS_PREFERENCE_UNSPECIFIED = 0;
  GAS_PREFERENCE_LOW = 1;                 // Optimize for cost
  GAS_PREFERENCE_MEDIUM = 2;              // Balance cost/speed
  GAS_PREFERENCE_HIGH = 3;                // Optimize for speed
  GAS_PREFERENCE_CUSTOM = 4;              // User-specified
}

message NotificationPreferences {
  bool transaction_confirmations = 1;
  bool price_alerts = 2;
  bool security_alerts = 3;
}
```

#### 5.2 Account Preferences

```proto
// Account-specific preference overrides
message AccountPreferences {
  // Optional overrides (if set, override identity defaults)
  optional uint32 default_chain_id = 1;
  optional GasPreference gas_preference = 2;
  optional uint32 default_slippage_bps = 3;

  // Account-specific settings
  bool require_confirmation = 4;          // Require extra confirmation for txs
  uint64 daily_limit_wei = 5;             // Optional daily spending limit
}
```

### 6. Signature Audit Trail

The signature audit trail provides a complete record of all signing operations performed by each account. Each account has its own audit log, enabling efficient lookup and append operations.

#### 6.1 Design Rationale

Rather than storing derived transaction data (which can be reconstructed from on-chain state), the audit trail stores:

1. **Signed preimages**: The exact data that was signed, enabling full reconstruction
2. **All signature types**: `eth_sign`, `personal_sign`, `eth_signTypedData_v4`, `eth_sendTransaction`
3. **Competing signatures**: Multiple signatures for the same nonce (only one executes on-chain)
4. **User annotations**: Memos and tags for organization

**Per-account storage** ensures:
- O(1) lookup for an account's signatures (via `AccountEntry.audit_ref`)
- Appending a signature only updates that account's audit log
- No cascading writes to other accounts or the registry
- Efficient pagination within a single account's history

#### 6.2 Schema Definition

```proto
// Per-account signature audit log
// Referenced from AccountEntry.audit_ref
message SignatureAuditLog {
  uint32 schema_version = 1;
  uint32 account_index = 2;               // For verification
  repeated SignatureRecord records = 3;
  google.protobuf.Timestamp last_updated = 4;
}

message SignatureRecord {
  // Unique identifier for this record
  bytes record_id = 1;                    // 32-byte unique ID (e.g., keccak256 of signature)

  // Signing context (account_index is in parent SignatureAuditLog)
  SignatureType type = 2;                 // Type of signature operation
  google.protobuf.Timestamp timestamp = 3;

  // The signed data (full preimage for reconstruction)
  oneof preimage {
    bytes raw_message = 4;                // For eth_sign, personal_sign
    TypedDataPreimage typed_data = 5;     // For eth_signTypedData_v4 (full EIP-712 data)
    bytes transaction_rlp = 6;            // For eth_sendTransaction (RLP-encoded tx)
    bytes eip7702_auth_rlp = 7;           // For EIP-7702 authorization (RLP-encoded)
  }

  // Chain context (for transactions)
  optional uint32 chain_id = 8;
  optional uint64 nonce = 9;              // Transaction nonce (for detecting replacements)

  // The signature itself
  bytes signature = 10;                   // 65-byte signature (r, s, v)

  // Execution status (for transactions)
  optional bytes tx_hash = 11;            // 32-byte hash if broadcast
  optional SignatureOutcome outcome = 12;

  // User annotations
  string memo = 13;                       // User-provided note
  repeated string tags = 14;              // User tags for categorization
}

// Full EIP-712 typed data for reconstruction
message TypedDataPreimage {
  // EIP-712 domain separator components
  string domain_name = 1;                 // Domain name
  string domain_version = 2;              // Domain version
  optional uint32 domain_chain_id = 3;    // Chain ID (if present)
  optional bytes domain_verifying_contract = 4;  // Contract address (20 bytes)
  optional bytes domain_salt = 5;         // Salt (32 bytes)

  // The structured data (JSON-encoded for maximum fidelity)
  string primary_type = 6;                // Primary type name
  string types_json = 7;                  // EIP-712 types definition (JSON)
  string message_json = 8;                // The message object (JSON)
}

enum SignatureType {
  SIGNATURE_TYPE_UNSPECIFIED = 0;
  SIGNATURE_TYPE_ETH_SIGN = 1;            // eth_sign (raw hash signing)
  SIGNATURE_TYPE_PERSONAL_SIGN = 2;       // personal_sign (prefixed message)
  SIGNATURE_TYPE_TYPED_DATA_V4 = 3;       // eth_signTypedData_v4 (EIP-712)
  SIGNATURE_TYPE_TRANSACTION = 4;         // eth_sendTransaction
  SIGNATURE_TYPE_EIP7702_AUTH = 5;        // EIP-7702 authorization
}

enum SignatureOutcome {
  SIGNATURE_OUTCOME_UNSPECIFIED = 0;
  SIGNATURE_OUTCOME_PENDING = 1;          // Not yet broadcast or awaiting confirmation
  SIGNATURE_OUTCOME_CONFIRMED = 2;        // On-chain and confirmed
  SIGNATURE_OUTCOME_FAILED = 3;           // On-chain but reverted
  SIGNATURE_OUTCOME_SUPERSEDED = 4;       // Different tx with same nonce confirmed
  SIGNATURE_OUTCOME_EXPIRED = 5;          // Authorization expired (e.g., EIP-7702 nonce passed)
}
```

#### 6.3 Audit Trail Opt-Out

Certain system operations generate high volumes of signatures that would create prohibitive storage overhead if logged. The `AuditPreferences` in `IdentityPreferences` (Section 5.1) controls which keys are excluded.

**Common exclusions**:
- `swarm_batch_owner` — Postage stamp signing (every chunk uploaded)
- `swarm_feed_owner` — Feed update signing (self-referential: audit storage generates more audit records)

**Rationale**:
- Swarm postage stamps require signing every chunk uploaded
- Storing audit records for these would create a self-referential loop
- System keys used for infrastructure operations may be excluded at user discretion

#### 6.4 Indexing

Within each per-account audit log, implementations SHOULD maintain indices for efficient queries:

- By chain ID (for transactions)
- By signature type
- By timestamp range
- By nonce (for detecting replacement transactions)

Cross-account queries (e.g., "all signatures in the last hour") require iterating over account audit logs, but this is expected to be rare compared to per-account queries.

### 7. Encryption Boundaries

#### 7.1 Per-Entity Encryption

Each storage unit is encrypted independently before storage:

```
┌─────────────────────────────────────┐
│  Version Manifest (encrypted)       │
│  - schema_versions                  │
│  - storage_refs → ─────────────────┐│
└────────────────────────────────────┘│
                                      │
┌─────────────────────────────────────┐│
│  Identity Core (encrypted)      ◄───┘
│  - name, avatar, preferences        │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  Account Registry (encrypted)       │
│  - AccountEntry[]                   │
│    ├─ details_ref → AccountDetails  │
│    └─ audit_ref → SignatureAuditLog │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  Account Details (encrypted)        │
│  (one per account)                  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  Signature Audit Log (encrypted)    │
│  (one per account, append-only)     │
│  - SignatureRecord[]                │
└─────────────────────────────────────┘
```

#### 7.2 Encryption Key Derivation

Per [Appendix I](/specs/appendix-i-system-key-registry), the storage encryption base key is used with domain separation to derive per-content encryption keys. Each storage unit uses a distinct domain for key derivation.

### 8. Size Considerations

This specification intentionally does not define explicit size limits for metadata fields. Practical limits are implied by the underlying storage architecture:

- **Swarm chunk size**: Content is stored in 4KB chunks with Merkle tree assembly for larger content
- **Encryption overhead**: AES-256-GCM adds nonce (12 bytes) and auth tag (16 bytes) per encrypted unit
- **Sync performance**: Larger metadata requires more chunks and longer sync times
- **Device constraints**: Mobile and embedded implementations may have memory limitations

Implementations SHOULD document any storage-specific limits they enforce and SHOULD handle oversized data gracefully (e.g., by rejecting with a clear error rather than silently truncating).

### 9. Validation Rules

#### 9.1 Required Fields

| Message | Required Fields |
|---------|-----------------|
| `VersionManifest` | `manifest_version`, `identity_index` |
| `IdentityCore` | `schema_version`, `index` |
| `AccountRegistry` | `schema_version` |
| `AccountEntry` | `account` oneof (either `native` or `provider`) |
| `AccountDetails` | `schema_version`, `account` oneof |

#### 9.2 Data Validation

Implementations MUST validate:

1. **Uniqueness**: Account identifiers must be unique within an identity (native indices and provider addresses occupy separate namespaces)
2. **Ranges**: For native accounts, `NativeAccount.index` must be within valid BIP-44 ranges
3. **Format**: For provider accounts, `ProviderAccount.address` must be exactly 20 bytes
4. **References**: Folder paths must be valid UTF-8
5. **Timestamps**: Created timestamps must not be in the future
6. **Consistency**: The `account` oneof in `AccountDetails` must match the corresponding `AccountEntry`
7. **Reference integrity**: All `details_ref` values must point to valid encrypted content

### 10. Relationship Encoding

#### 10.1 Storage Hierarchy

```
Version Manifest (deterministic location)
├── storage_refs["identity_core"] → IdentityCore
├── storage_refs["account_registry"] → AccountRegistry
│   └── accounts[]
│       ├── AccountEntry (index: 0)
│       │   └── details_ref → AccountDetails
│       ├── AccountEntry (index: 1)
│       │   └── details_ref → AccountDetails
│       └── ...
└── storage_refs["signature_audit"] → SignatureAuditTrail
```

#### 10.2 Cross-Identity References

Per [NXP-1 Section 7](/specs/nxp-1-identity-model#7-identity-metadata), cross-identity references are **prohibited**. Metadata MUST NOT contain:

- References to other identity indices
- Shared folder structures
- Tags that span identities
- Any data that could link identities

## Implementation Requirements

### MUST

1. Use protobuf for all metadata serialization
2. Include `schema_version` in all top-level messages
3. Support reading all previous schema versions
4. Encrypt all identity metadata before storage
5. Validate all fields against constraints
6. Enforce cross-identity isolation

### SHOULD

1. Implement efficient migration paths
2. Provide schema validation utilities
3. Support incremental sync for signature audit trail
4. Index signature audit trail for efficient queries

### MAY

1. Support additional account categories
2. Extend preferences with implementation-specific fields
3. Implement local caching of decoded metadata

## References

- [NXP-1: Identity Model](/specs/nxp-1-identity-model)
- [NXP-2: Derivation Path Standards](/specs/nxp-2-derivation-path-standards)
- [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry)
- [Protocol Buffers](https://protobuf.dev/)
- [GitHub Issue #88](https://github.com/nxm-rs/nexum/issues/88)

## Changelog

### Version 1.0.0 (2025-12-08)

- Initial NXP-3 specification
- Define storage-aware schema design with version manifest
- Separate storage units by update frequency (identity core, account registry, account details, signature audit)
- Add `AccountKeySource` enum for native vs delegated accounts
- Specify preferences structure including audit trail configuration
- Define signature audit trail for complete signing history
- Support audit opt-out for high-volume system keys (preventing self-referential storage loops)
- Establish per-entity versioning and migration strategy
- Define per-entity encryption boundaries

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
