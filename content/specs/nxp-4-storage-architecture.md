+++
title = "NXP-4: Storage Architecture"
date = "2025-12-07"
weight = 4
slug = "nxp-4-storage-architecture"
description = "Decentralized storage architecture for Nexum built on Ethereum Swarm, specifying AES-256-GCM encryption with deterministic key derivation, feed structures for mutable metadata, and deterministic identity metadata locations enabling enumeration and recovery"

[taxonomies]
tags=["specification", "storage", "swarm", "encryption", "feeds", "AES-GCM", "EIP-1581", "NXP"]

[extra]
author = "mfw78"
+++

## Abstract

This specification (NXP-4) defines the storage architecture for Nexum, built on [Ethereum Swarm](https://www.ethswarm.org/). It specifies how profile metadata, preferences, and wallet state are stored, encrypted, and synchronized using Swarm's content-addressed storage and feed mechanisms.

NXP-4 builds on [NXP-2 (Derivation Path Standards)](/specs/nxp-2-derivation-path-standards) and [NXP-3 (Metadata Schema)](/specs/nxp-3-metadata-schema) for key derivation and data structures, utilizing the system key allocations defined in [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry).

## Motivation

Nexum requires decentralized storage that:

1. **Preserves privacy**: Sensitive metadata must be encrypted
2. **Enables sync**: Multiple devices can access the same profile data
3. **Supports recovery**: Data can be reconstructed from seed phrase + known conventions
4. **Avoids centralization**: No reliance on centralized servers
5. **Integrates with identity**: Storage tied to cryptographic identity

Ethereum Swarm provides content-addressed storage with feeds (mutable pointers) and postage batches (payment for storage), making it ideal for this use case.

## Specification

### 1. System Keys for Storage

NXP-4 uses system keys defined in [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry) for Swarm operations.

#### 1.1 Signing Keys

NXP-4 requires the following signing keys from [Appendix I §2.2](/specs/appendix-i-system-key-registry#22-signing-key-registry):

**Batch Owner Key**:
- Signs all postage stamps for uploaded chunks
- Address becomes immutable batch owner when batch is created
- Note: Batches can be purchased by *any* address; the owner is specified at purchase time and need not be the purchaser
- Due to high signing volume (every chunk uploaded requires a stamp), implementations MAY use an EIP-1581 derived key that can be exported for local machine signing (see Section 1.3)

**Feed Owner Key**:
- Signs feed updates (Single Owner Chunks)
- Feed address = `keccak256(feed_id || owner_address)`
- All updates to a feed must use this key

#### 1.2 Encryption Keys

NXP-4 requires the following encryption key from [Appendix I §3.2](/specs/appendix-i-system-key-registry#32-encryption-key-registry):

**Storage Encryption Key**:
- 32-byte key for chunk encryption
- Exportable from Keycard (EIP-1581 subtree)
- Used directly or to derive per-content keys

#### 1.3 Batch Owner Key Derivation Options

The batch owner key has uniquely high signing throughput requirements—every chunk uploaded requires a stamp signature. To accommodate different security/performance tradeoffs, Nexum supports two derivation strategies:

| Strategy | Derivation | Exportable | Signing | Use Case |
|----------|------------|------------|---------|----------|
| **BIP-44 (on-card)** | `m/44'/60'/identity'/0/system_index` | No | On Keycard | Maximum security, lower throughput |
| **EIP-1581 (exportable)** | `m/43'/60'/1581'/identity'/0` | Yes | Local machine | High throughput, key held in memory |

**BIP-44 Strategy**:
- Key derived per [Appendix I §2.2](/specs/appendix-i-system-key-registry#22-signing-key-registry)
- Signing occurs on Keycard hardware
- Throughput limited by card I/O (typically ~5 signatures/second)
- Suitable for low-frequency uploads or security-critical deployments

**EIP-1581 Strategy**:
- Key derived from EIP-1581 subtree (non-wallet keys)
- Private key exportable from Keycard
- Signing occurs on local machine (thousands of signatures/second)
- Suitable for bulk uploads, frequent metadata updates

Implementations SHOULD:
1. Default to BIP-44 for new identities (security-first)
2. Allow users to opt into EIP-1581 derivation for high-throughput scenarios
3. Store the derivation strategy choice in identity preferences

**Important**: Both strategies produce different addresses. Once a batch is created with a specific owner address, that owner is immutable. Switching strategies requires creating new batches.

### 2. Swarm Primitives

#### 2.1 Content-Addressed Chunks (CAC)

Immutable chunks addressed by content hash:

```
address = BMT_hash(data)
```

- Maximum 4KB per chunk
- Larger content split into Merkle tree of chunks
- Encrypted chunks use random key embedded in reference (64 bytes)

#### 2.2 Single Owner Chunks (SOC)

Mutable pointers owned by a key:

```
SOC_address = keccak256(soc_id || owner_address)
```

- Signed by owner's private key
- Can be updated (new SOC at same address)
- Used as basis for feeds

#### 2.3 Feeds

Versioned sequences of SOCs:

```
feed_id = keccak256(topic || index_bytes)
feed_address = keccak256(feed_id || owner_address)
```

- Topic: arbitrary bytes identifying the feed purpose
- Index: sequence number or epoch-based
- Each update is a signed SOC pointing to content

#### 2.4 Postage Batches

Payment for storage:

- Purchased on-chain with BZZ tokens
- Batch owner signs stamps for uploaded chunks
- Batch ID + stamp authorizes storage

### 3. Encryption Scheme

#### 3.1 Deterministic Encryption

For identity metadata that must be recoverable:

```python
from Crypto.Cipher import AES
from Crypto.Random import get_random_bytes
from eth_hash.auto import keccak

def derive_base_key(seed: bytes) -> bytes:
    """
    Derive base encryption key from EIP-1581 path.
    See Appendix I for the specific path.
    """
    # Path defined in Appendix I: System Key Registry
    return derive_storage_encryption_key(seed)

def derive_content_key(base_key: bytes, content_id: str) -> bytes:
    """Derive per-content encryption key using domain separation."""
    return keccak(base_key + content_id.encode())

def encrypt_content(content: bytes, content_id: str, base_key: bytes) -> bytes:
    """Encrypt content with AES-256-GCM."""
    key = derive_content_key(base_key, content_id)
    nonce = get_random_bytes(12)
    cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
    ciphertext, tag = cipher.encrypt_and_digest(content)
    return nonce + ciphertext + tag
```

#### 3.2 Content Identifiers

Standard content identifiers for deterministic key derivation:

| Content ID | Purpose |
|------------|---------|
| `profile.metadata` | Profile metadata JSON |
| `profile.preferences` | User preferences |
| `accounts.labels` | Account metadata/labels |
| `accounts.folders` | Folder structure |

#### 3.3 Encryption Format

```
[nonce (12 bytes)][ciphertext][auth_tag (16 bytes)]
```

- Algorithm: AES-256-GCM
- Nonce: Random 12 bytes (prepended to ciphertext)
- Auth tag: 16 bytes (appended)

### 4. Feed Structure

#### 4.1 Indexed Feeds for Versioned Storage

All identity storage units use **indexed feeds**—Swarm feeds with sequential integer indices. Each update increments the index, creating an append-only history of all changes.

**Benefits of indexed feeds:**
- **Time-travel**: Navigate backwards through indices to see historical wallet state
- **Audit trail**: Every configuration change is preserved
- **Recovery**: Reconstruct wallet state at any point in time
- **Conflict detection**: Concurrent updates create gaps or forks in the index sequence

**Feed structure:**

```
feed_address = keccak256(feed_id || owner_address)

where:
  topic    = keccak256(abi.encode(topic_prefix, identity_index))
  feed_id  = keccak256(topic || abi.encode(index))
  owner    = feed_owner_key (per Appendix I)
```

The `index` is incremented with each update. To read the latest state, implementations query for the highest known index.

#### 4.2 Deterministic Metadata Location

Per [NXP-1 Section 5.2](/specs/nxp-1-identity-model#52-enumeration), identity metadata is stored at a deterministic location derived from the identity index.

**Version Manifest Location:**

The version manifest (root document) for each identity is stored at:

```
topic = keccak256(abi.encode("nexum.identity.manifest", identity_index))
```

This provides:
- **Deterministic**: Same seed + identity index always yields same location
- **Identity-scoped**: Each identity has a unique, independent location
- **Owner-bound**: Only the identity's feed owner key can update

#### 4.3 Storage Unit Topics

Each storage unit (per [NXP-3](/specs/nxp-3-metadata-schema)) has its own feed topic:

| Storage Unit | Topic Prefix | Update Frequency |
|--------------|--------------|------------------|
| Version Manifest | `nexum.identity.manifest` | On any sub-entity change |
| Identity Core | `nexum.identity.core` | Infrequently |
| Account Registry | `nexum.identity.accounts` | Occasionally |
| Account Details | `nexum.account.details.{index}` | Per-account |
| Signature Audit | `nexum.account.audit.{index}` | Per-account, continuously |

**Note**: Account-level feeds include the account index in the topic prefix to provide independent versioning per account.

#### 4.4 Identity Enumeration

```python
from eth_abi import encode

# Well-known topic prefix for version manifest
VERSION_MANIFEST_TOPIC_PREFIX = "nexum.identity.manifest"

def compute_manifest_location(seed: bytes, identity: int, index: int = 0) -> bytes:
    """
    Compute the Swarm feed address for an identity's version manifest.
    Use index=0 for latest, or specific index for historical state.
    """
    # 1. Compute deterministic topic from identity index
    topic = keccak(encode(['string', 'uint256'], [VERSION_MANIFEST_TOPIC_PREFIX, identity]))

    # 2. Derive feed owner for this identity (path per Appendix I)
    feed_owner = derive_feed_owner_key(seed, identity)

    # 3. Compute feed address for the given index
    feed_id = keccak(topic + encode(['uint256'], [index]))
    feed_address = keccak(feed_id + feed_owner.address)

    return feed_address

def enumerate_identities(seed: bytes, max_gap: int = 20) -> list[int]:
    """
    Enumerate all identities by checking for version manifests.
    """
    identities = []
    consecutive_empty = 0
    identity = 0

    while consecutive_empty < max_gap:
        # Check if any version of the manifest exists (start with index 0)
        location = compute_manifest_location(seed, identity, index=0)
        if feed_exists_at(location):
            identities.append(identity)
            consecutive_empty = 0
        else:
            consecutive_empty += 1
        identity += 1

    return identities

def get_historical_state(seed: bytes, identity: int, index: int) -> VersionManifest:
    """
    Retrieve wallet state at a specific point in history.
    """
    location = compute_manifest_location(seed, identity, index)
    encrypted = fetch_feed_at(location)
    return decrypt_and_parse(encrypted)
```

#### 4.5 Feed Update Structure

Each feed update is encoded as protobuf:

```proto
syntax = "proto3";

package nexum.storage;

message FeedUpdate {
  uint32 schema_version = 1;                  // Schema version (current: 1)
  uint64 index = 2;                           // Sequential feed index (for time-travel)
  uint64 timestamp = 3;                       // Unix timestamp
  bytes content_ref = 4;                      // Swarm reference to encrypted content
  EncryptionInfo encryption = 5;
  optional uint64 previous_index = 6;         // Previous index (for chain verification)
}

message EncryptionInfo {
  string algorithm = 1;                       // e.g., "aes-256-gcm"
  string content_id = 2;                      // Content ID for key derivation
}
```

Content integrity is verified intrinsically by Swarm's content-addressed storage (BMT hash), so no separate content hash field is needed.

**Example:**

```
FeedUpdate {
  schema_version: 1
  index: 42
  timestamp: 1701936000
  content_ref: <32-byte swarm reference>
  encryption {
    algorithm: "aes-256-gcm"
    content_id: "nexum.identity.manifest"
  }
  previous_index: 41
}
```

#### 4.6 Discovery

Given a seed phrase and identity index, discover and retrieve metadata:

1. Compute version manifest location using `compute_manifest_location(seed, identity)`
2. Fetch latest feed update from Swarm (highest known index)
3. Derive encryption key (per [Appendix I](/specs/appendix-i-system-key-registry))
4. Decrypt version manifest
5. Follow `storage_refs` to fetch sub-entities as needed

### 5. Storage Patterns

#### 5.1 Encrypted Metadata Upload

```python
from dataclasses import dataclass

@dataclass
class IdentityKeys:
    batch_owner: KeyPair
    feed_owner: KeyPair
    encryption_key: bytes

def derive_identity_keys(seed: bytes, identity: int) -> IdentityKeys:
    """
    Derive all system keys for an identity.
    Paths defined in Appendix I: System Key Registry.
    """
    return IdentityKeys(
        batch_owner=derive_batch_owner_key(seed, identity),
        feed_owner=derive_feed_owner_key(seed, identity),
        encryption_key=derive_storage_encryption_key(seed)
    )

async def upload_identity_metadata(
    bee: Bee,
    seed: bytes,
    identity: int,
    metadata: bytes
) -> bytes:
    """Upload encrypted identity metadata to Swarm."""
    # 1. Derive keys (per Appendix I)
    keys = derive_identity_keys(seed, identity)

    # 2. Encrypt metadata
    encrypted = encrypt_content(metadata, 'identity.metadata', keys.encryption_key)

    # 3. Upload encrypted chunk (stamped by batch owner)
    chunk_ref = await bee.upload_data(encrypted, signer=keys.batch_owner.private_key)

    # 4. Update feed (signed by feed owner)
    topic = compute_feed_topic(identity)
    await bee.set_feed_update(topic, chunk_ref, signer=keys.feed_owner.private_key)

    return chunk_ref
```

#### 5.2 Metadata Retrieval

```python
def decrypt_content(encrypted: bytes, content_id: str, base_key: bytes) -> bytes:
    """Decrypt AES-256-GCM encrypted content."""
    key = derive_content_key(base_key, content_id)
    nonce = encrypted[:12]
    tag = encrypted[-16:]
    ciphertext = encrypted[12:-16]

    cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
    return cipher.decrypt_and_verify(ciphertext, tag)

async def get_identity_metadata(
    bee: Bee,
    seed: bytes,
    identity: int
) -> bytes:
    """Retrieve and decrypt identity metadata from Swarm."""
    # 1. Derive keys
    keys = derive_identity_keys(seed, identity)

    # 2. Compute feed topic
    topic = compute_feed_topic(identity)

    # 3. Fetch latest feed update
    feed_update = await bee.get_feed_update(topic, keys.feed_owner.address)
    encrypted = await bee.download_data(feed_update.reference)

    # 4. Decrypt
    return decrypt_content(encrypted, 'identity.metadata', keys.encryption_key)
```

### 6. Local Storage

#### 6.1 Cache Structure

Local cache mirrors Swarm content:

```
~/.nexum/
├── profiles/
│   ├── 0/
│   │   ├── metadata.json.enc    # Encrypted profile metadata
│   │   ├── preferences.json.enc # Encrypted preferences
│   │   └── cache/
│   │       └── feeds/           # Cached feed states
│   └── 1/
│       └── ...
├── swarm/
│   ├── chunks/                  # Cached chunks by address
│   └── feeds/                   # Feed state cache
└── config.json                  # Non-sensitive local config
```

#### 6.2 Sync Strategy

1. **On startup**: Fetch latest feed updates from Swarm
2. **On change**: Update local cache, push to Swarm
3. **Conflict resolution**: Latest timestamp wins (feeds are append-only)
4. **Offline support**: Queue changes, sync when online

### 7. Security Considerations

#### 7.1 Key Separation

- **Signing keys** (BIP-44): Never exported, on-card signing—except batch owner key when using EIP-1581 strategy (see Section 1.3)
- **Encryption keys** (EIP-1581): Exportable, but no funds at risk
- **Batch owner key** (EIP-1581 strategy): Exportable for throughput; compromise only affects storage stamps, not funds

#### 7.2 Encryption Key Derivation

- Base key derived from seed (deterministic)
- Per-content keys derived with domain separation
- Loss of seed = loss of decryption capability

#### 7.3 Feed Authenticity

- Feed updates signed by owner key
- Signature verified on retrieval
- Prevents tampering by storage providers

#### 7.4 Metadata Privacy

- All sensitive data encrypted before upload
- Content identifiers are not secret (domain separation)
- Feed addresses reveal owner's public key

### 8. Implementation Requirements

#### 8.1 MUST

1. Use system keys as defined in [Appendix I](/specs/appendix-i-system-key-registry) for Swarm operations
2. Encrypt all sensitive metadata before upload
3. Store identity metadata at deterministic locations per Section 4.1
4. Use the well-known topic prefix `nexum.identity.metadata` for identity feeds
5. Verify feed signatures on retrieval

#### 8.2 SHOULD

1. Cache feed state locally for offline access
2. Implement conflict resolution for concurrent updates
3. Support background sync for multi-device scenarios

#### 8.3 MAY

1. Support alternative storage backends (local-only mode)
2. Implement chunk deduplication
3. Support selective sync (partial metadata)

### 9. References

- [NXP-1: Identity Model](/specs/nxp-1-identity-model)
- [NXP-2: Derivation Path Standards](/specs/nxp-2-derivation-path-standards)
- [NXP-3: Metadata Schema](/specs/nxp-3-metadata-schema)
- [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry)
- [Ethereum Swarm Documentation](https://docs.ethswarm.org/)
- [Swarm Bee](https://github.com/ethersphere/bee)
- [EIP-1581: Non-wallet usage of keys](https://eips.ethereum.org/EIPS/eip-1581)

## Changelog

### Version 1.0.0 (2025-12-07)

- Initial NXP-4 specification (renumbered from NXP-3)
- Define key derivation for Swarm operations (from NXP-2)
- Specify encryption scheme and feed structure
- Document storage patterns and local caching

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
