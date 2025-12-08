+++
title = "NXP-2: Derivation Path Standards"
date = "2025-12-08"
weight = 2
slug = "nxp-2-derivation-path-standards"
description = "A hierarchical key derivation standard combining BIP-44 with metadata-based organization and zero-metadata delegation key derivation, compatible with Keycard's 10-node depth limit"

[taxonomies]
tags=["specification", "derivation", "BIP32", "BIP44", "keycard", "identity", "delegation", "NXP"]

[extra]
author = "mfw78"
+++

## Abstract

This specification (NXP-2) defines a hierarchical key derivation standard that combines two complementary approaches:

1. **Metadata-labeled accounts**: Standard [BIP-44](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki) derivation with rich metadata providing folder/file organizational semantics
2. **Identity-scoped delegation keys**: Deterministic key derivation from external addresses, nested under identity for gas tank routing and isolation

This hybrid design enables flexible key organization while supporting deterministic derivation of delegation keys without requiring any stored metadata, while maintaining strict identity isolation.

## Motivation

### The Metadata Trade-off

Traditional [BIP-44](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki) uses gap-limit scanning (20 consecutive empty addresses) to discover accounts. This works but:

- Requires on-chain activity for discovery
- Provides no semantic organization
- Cannot express folder/file structures

An alternative approach using hash-based derivation (e.g., `keccak256("path.to.key")` → indices) was considered, but this **still requires metadata** to store the logical path strings for reconstruction.

**Key insight**: If metadata is required anyway for organizational naming, sequential BIP-44 indices with metadata labels is simpler and more flexible—renaming or reorganizing is just a metadata change without affecting the underlying keys.

### The Delegation Problem

However, there exists a use case where **zero-metadata discovery** is valuable: determining if a seed phrase can derive a key related to a known external address.

Examples:
- "Can this seed control the EIP-7702 delegation for address X?"
- "Does this seed have a signer key for multisig Y?"
- "Can I derive a migration key for legacy account Z?"

For these cases, the external address itself serves as the lookup key, requiring no stored metadata.

**Identity scoping requirement**: Delegation keys must be nested under a specific identity to enable:
- Deterministic gas tank routing (each identity has its own gas tank)
- Strict identity isolation (no cross-identity bleed)
- EIP-7702 + ERC-4337 paymaster scenarios

### Design Goals

1. **Organizational flexibility**: Folder/file semantics via metadata labels
2. **Rename/move without re-keying**: Metadata changes don't affect derivation
3. **Zero-metadata delegation**: Discover keys from external addresses alone
4. **Identity isolation**: Delegation keys scoped to identity for gas tank routing
5. **[Keycard](https://github.com/status-im/status-keycard) compatibility**: Stay within 10 derivation nodes
6. **BIP-32/44 compatibility**: Build on existing standards

## Specification

### 1. Overview

NXP-2 defines two derivation schemes:

| Scheme | Purpose | Discovery | Metadata Required | Identity-Scoped |
|--------|---------|-----------|-------------------|-----------------|
| Labeled Accounts | General key management | Gap-limit or metadata | Yes (for labels) | Yes |
| Delegation Keys | External address binding | Address-based | No | Yes |

### 2. Labeled Accounts (BIP-44 + Metadata)

#### 2.1 Derivation Path

Standard BIP-44 structure:

```
m / 44' / coin_type' / account' / change / address_index
```

For Ethereum:
```
m / 44' / 60' / account' / 0 / address_index
```

Where:
- `44'` — BIP-44 purpose (hardened)
- `60'` — Ethereum coin type (hardened)
- `account'` — Account index, hardened, provides profile isolation
- `0` — External chain (receive addresses)
- `address_index` — Sequential index within account

#### 2.2 Profile Isolation via Account Index

The hardened `account'` level provides **complete profile separation**:

```
m/44'/60'/0'/...  — Profile 0 (e.g., Personal)
m/44'/60'/1'/...  — Profile 1 (e.g., Work)
m/44'/60'/2'/...  — Profile 2 (e.g., Pseudonymous)
```

Each profile:
- Is cryptographically isolated (compromise of one cannot affect others)
- Has its own independent metadata store
- Presents as an entirely separate identity in wallet UIs
- MUST NOT share folder structures or metadata with other profiles

#### 2.3 Metadata-Based Organization

Accounts within an identity are organized using metadata that associates human-readable labels and folder structures with sequential `address_index` values. This approach provides:

- **Decoupled organization**: Folder/file semantics exist purely in metadata, not in derivation paths
- **Stable keys**: Renaming or reorganizing accounts changes only metadata, not underlying keys
- **Sequential indices**: Accounts use sequential `address_index` values regardless of organizational structure

Per [NXP-1 Section 7](/specs/nxp-1-identity-model#7-identity-metadata), organizational metadata MUST NOT span multiple identities.

#### 2.4 Discovery

Identities are discovered via deterministic metadata locations as defined in [NXP-1 Section 5.2](/specs/nxp-1-identity-model#52-enumeration). Discovery iterates through identity indices and retrieves metadata from each deterministic location.

**Optional fallback**: Implementations MAY support BIP-44 gap-limit scanning (20 consecutive empty addresses) for recovery when metadata is unavailable. This recovers accounts but not organizational structure.

### 3. Delegation Keys (Identity-Scoped, Zero-Metadata Derivation)

#### 3.1 Purpose

Delegation keys enable deterministic derivation of keys associated with external addresses, scoped to a specific identity. Given a seed phrase, identity index, and external address, derive a unique key for that combination.

Use cases:
- **EIP-7702 delegation**: Derive a key that can act on behalf of a delegating EOA
- **Multisig participation**: Derive a signer key for a known multisig address
- **Account migration**: Derive a key bound to a legacy account being migrated

**Critical requirement**: Delegation keys MUST be identity-scoped to:
- Enable deterministic gas tank routing (identity's gas tank pays for delegation operations)
- Prevent cross-identity correlation
- Support EIP-7702 + ERC-4337 paymaster scenarios

#### 3.2 Derivation Path (Ethereum Only)

Delegation keys nest under the BIP-44 identity level, using the `change` position to separate them from standard accounts:

```
m / 44' / 60' / identity' / 1 / addr[0]' / addr[1]' / addr[2]' / addr[3]' / addr[4]'
```

Where:
- `44'` — BIP-44 purpose (hardened)
- `60'` — Ethereum coin type (hardened)
- `identity'` — Identity index (hardened), per [NXP-1](/specs/nxp-1-identity-model)
- `1` — Change level set to 1 (internal chain), separating delegation keys from standard accounts which use change=0
- `addr[0..4]'` — 20-byte address split into 5 × 4-byte chunks, each as hardened index

Total depth: **10 levels** (exactly at Keycard's limit)

**Note**: This derivation scheme is Ethereum-specific (20-byte addresses). Chains with longer addresses would exceed Keycard's 10-node limit and are out of scope.

#### 3.3 Address-to-Indices Conversion

Given a 20-byte Ethereum address, derive 5 hardened indices:

1. **Interpret** address bytes in big-endian order
2. **Partition** into 5 × 4-byte chunks
3. **Convert** each chunk to uint32
4. **Apply** hardened flag (set bit 31)

```python
HARDENED_OFFSET = 0x80000000  # 2³¹

def address_to_indices(address: bytes) -> list[int]:
    """Convert a 20-byte Ethereum address to 5 hardened BIP-32 indices."""
    assert len(address) == 20, "Delegation keys only support 20-byte addresses"

    indices = []
    for i in range(0, 20, 4):
        chunk = address[i:i+4]
        value = int.from_bytes(chunk, byteorder='big')
        indices.append(value | HARDENED_OFFSET)

    return indices  # Always exactly 5 indices
```

#### 3.4 BIP-32 Derivation Validity

Per [BIP-32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#child-key-derivation-ckd-functions), child key derivation can fail in rare cases:

1. When `parse₂₅₆(I_L) ≥ n` (curve order)
2. When the resulting key equals zero or point at infinity

**Probability**: < 2⁻¹²⁷ per derivation (essentially never in practice)

**Required behavior**: If derivation fails for index `i`, increment to `i+1` and retry.

#### 3.5 Deterministic Derivation Algorithm

To ensure all implementations arrive at the same key for a given (identity, address) pair, the following deterministic algorithm MUST be used:

```python
import hmac
import hashlib
from dataclasses import dataclass

# secp256k1 curve order
SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

@dataclass
class ExtendedKey:
    private_key: int
    chain_code: bytes

def try_derive(parent: ExtendedKey, index: int) -> ExtendedKey | None:
    """Attempt to derive a child key. Returns None if derivation is invalid."""
    data = serialize(parent, index)
    i = hmac.new(parent.chain_code, data, hashlib.sha512).digest()
    i_l, i_r = i[:32], i[32:]

    # Check validity per BIP-32
    parsed_key = int.from_bytes(i_l, byteorder='big')
    if parsed_key >= SECP256K1_ORDER:
        return None  # Invalid: I_L >= curve order

    child_key = (parsed_key + parent.private_key) % SECP256K1_ORDER
    if child_key == 0:
        return None  # Invalid: resulting key is zero

    return ExtendedKey(private_key=child_key, chain_code=i_r)

def derive_with_retry(parent: ExtendedKey, start_index: int) -> tuple[ExtendedKey, int]:
    """Derive child key, incrementing index on failure until valid."""
    index = start_index

    while True:
        result = try_derive(parent, index)
        if result is not None:
            return (result, index)
        index += 1  # Increment and retry

        # Safety check (should never be reached in practice)
        if index > 0xFFFFFFFF:
            raise ValueError("Exhausted index space")

def derive_delegation_key(
    master_key: ExtendedKey,
    identity: int,
    address: bytes
) -> ExtendedKey:
    """Derive delegation key for an address within a specific identity."""
    address_indices = address_to_indices(address)

    # Derive BIP-44 path: m/44'/60'/identity'/1
    current, _ = derive_with_retry(master_key, 44 | HARDENED_OFFSET)
    current, _ = derive_with_retry(current, 60 | HARDENED_OFFSET)
    current, _ = derive_with_retry(current, identity | HARDENED_OFFSET)
    current, _ = derive_with_retry(current, 1)  # change=1 (internal chain) for delegation

    # Derive each address-derived index with retry
    for index in address_indices:
        current, _ = derive_with_retry(current, index)

    return current
```

**Key properties:**
- **Identity-scoped**: Same address with different identity produces different key
- **Deterministic**: Same (identity, address) always produces same key
- **No metadata**: Algorithm handles retries internally
- **BIP-32 compliant**: Properly handles invalid derivations
- **Practically identical**: Retry probability < 2⁻¹²⁷ per level

#### 3.6 Discovery Algorithm

To derive a delegation key for address X within identity N:

```python
@dataclass
class DelegationKeyResult:
    public_key: bytes
    derived_address: bytes
    path: str

def get_delegation_key(
    seed: bytes,
    identity: int,
    address: bytes
) -> DelegationKeyResult:
    """Derive a delegation key for an address within an identity."""
    master_key = derive_master_key(seed)
    delegation_key = derive_delegation_key(master_key, identity, address)

    return DelegationKeyResult(
        public_key=to_public_key(delegation_key),
        derived_address=to_ethereum_address(delegation_key),
        path=f"m/44'/60'/{identity}'/1/addr[0..4]'"
    )
```

This requires **no metadata**—the identity index and target address are sufficient for derivation.

#### 3.7 Gas Tank Routing

Because delegation keys are identity-scoped, gas tank routing is deterministic:

```
Identity 0:
├── Gas Tank: (system account per Appendix I)
├── Delegation for 0xAAA...: m/44'/60'/0'/1/...
└── Delegation for 0xBBB...: m/44'/60'/0'/1/...

Identity 1:
├── Gas Tank: (system account per Appendix I)
├── Delegation for 0xAAA...: m/44'/60'/1'/1/...  (different key!)
└── Delegation for 0xCCC...: m/44'/60'/1'/1/...
```

When an EIP-7702 delegated transaction needs gas sponsorship:
1. Identify which identity owns the delegation key
2. Route payment through that identity's gas tank (see [Appendix I §2.2](/specs/appendix-i-system-key-registry#22-signing-key-registry))
3. No ambiguity—each delegation key belongs to exactly one identity

#### 3.8 Authorization

For a delegation key to be useful, the derived key's address must be authorized to act on behalf of the target address:

1. **EIP-7702**: The delegating EOA signs an authorization designating a smart contract that recognizes the derived key's address
2. **Multisig**: Add derived key's address as a signer
3. **Smart accounts**: Register derived key in account's access control

Authorization may exist in two states:
- **Pending**: A signed authorization exists but has not yet been submitted on-chain (e.g., signed for the next nonce)
- **Active**: The authorization has been executed on-chain

Both states represent valid delegation relationships. Pending authorizations enable batched submission (e.g., via gas tank sponsorship) and offline signing workflows.

#### 3.9 Identity Isolation

Delegation keys enforce strict identity isolation:

- Same external address → different delegation key per identity
- No way to derive Identity 1's delegation key from Identity 0's keys
- Sharing a delegate across identities requires registering different derived addresses

### 4. Keycard Integration

#### 4.1 Depth Analysis

| Scheme | Path | Levels | Within Limit |
|--------|------|--------|--------------|
| BIP-44 Accounts | `m/44'/60'/id'/0/index` | 5 | ✓ |
| Delegation Keys | `m/44'/60'/id'/1/a0'/a1'/a2'/a3'/a4'` | 10 | ✓ (exact) |

Delegation keys use the maximum Keycard depth of 10 levels, leaving no room for additional derivation.

#### 4.2 Key Export Restrictions

Per Keycard security model:

| Path | Exportable | Notes |
|------|------------|-------|
| `m/44'/60'/*/0/*` | No | Standard accounts stay on-card |
| `m/44'/60'/*/1/*` | No | Delegation keys stay on-card |
| `m/43'/60'/1581'/*` | Yes | EIP-1581 encryption keys only |

Encryption operations requiring private key export MUST use the EIP-1581 subtree.

#### 4.3 Signing Operations

Both labeled accounts and delegation keys support on-card signing:

```
DERIVE KEY → SIGN → (key never leaves card)
```

### 5. Index Space Partitioning

To support both user-controlled accounts and system-reserved accounts within each identity, the `address_index` space is partitioned. The specific partitioning values and system key allocations are defined in [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry).

#### 5.1 Partitioning Overview

The index space is divided into two regions:

| Range | Purpose |
|-------|---------|
| Below SYSTEM_OFFSET | User accounts |
| SYSTEM_OFFSET and above | System accounts |

See [Appendix I §1](/specs/appendix-i-system-key-registry#1-index-space-partitioning) for the specific offset value.

#### 5.2 BIP-44 Index Partitioning

```
m/44'/60'/identity'/0/index

Index allocation:
├── User range    → User accounts (metadata-labeled)
└── System range  → System accounts (Nexum reserved)
```

System account assignments are defined in [Appendix I §2](/specs/appendix-i-system-key-registry#2-signing-keys-bip-44).

#### 5.3 EIP-1581 Index Partitioning

```
m/43'/60'/1581'/key_type'/index

Index allocation:
├── User range    → User encryption keys
└── System range  → System encryption keys
```

System encryption key assignments are defined in [Appendix I §3](/specs/appendix-i-system-key-registry#3-encryption-keys-eip-1581).

#### 5.4 Per-Identity Isolation

Each identity has its own independent index space. System keys are identity-scoped—each identity has its own independent system keys.

### 6. Key Relationship Summary

```
Identity N
│
├── User Accounts (BIP-44, non-exportable)
│   └── m/44'/60'/N'/0/{user range}
│       └── Metadata-labeled accounts (folder/file org)
│
├── System Accounts (BIP-44, non-exportable)
│   └── m/44'/60'/N'/0/{system range}
│       └── Per Appendix I allocations
│
├── User Encryption (EIP-1581, exportable)
│   └── m/43'/60'/1581'/1'/{user range}
│       └── User-controlled encryption keys
│
└── System Encryption (EIP-1581, exportable)
    └── m/43'/60'/1581'/1'/{system range}
        └── Per Appendix I allocations
```

### 7. Security Considerations

#### 7.1 Hardened Derivation

All sensitive paths use hardened derivation:
- BIP-44: purpose, coin_type, identity are hardened
- Delegation: identity and all address indices are hardened

This ensures child key compromise cannot endanger parent or sibling keys.

#### 7.2 Identity Isolation

Delegation keys enforce identity isolation:
- Same external address produces different delegation keys per identity
- No cross-identity key derivation possible
- Gas tank routing is unambiguous (each delegation key → one identity → one gas tank)

#### 7.3 Metadata Security

Labeled account metadata reveals organizational structure but not keys. Still:
- Metadata SHOULD be encrypted at rest
- Loss of metadata loses organization, not keys (gap-limit recovery still works)

#### 7.4 Delegation Key Binding

Delegation keys are cryptographically bound to (identity, address) pairs:
- Different identity OR different address → different key
- No way to derive delegation key without knowing both identity and target address
- Authorization (on-chain or pending) required for key to have any authority

#### 7.5 Address Collision

For 20-byte addresses split into 5 indices, collision requires matching all 160 bits. The probability of two different addresses producing the same delegation key within an identity is 2⁻¹⁶⁰, which is negligible.

### 8. Implementation Requirements

#### 8.1 MUST

1. Support BIP-44 derivation for standard accounts
2. Use hardened derivation for all address indices in delegation paths
3. Stay within 10 derivation levels for Keycard compatibility
4. Encrypt metadata at rest
5. Support identity/account discovery via deterministic metadata location

#### 8.2 SHOULD

1. Implement folder/file UI for metadata labels within identities
2. Provide delegation key discovery given external address
3. Support metadata backup/restore

#### 8.3 MAY

1. Support additional coin types beyond Ethereum
2. Implement cross-device metadata synchronization
3. Provide migration tools from other organizational schemes
4. Support BIP-44 gap-limit scanning as fallback recovery

### 9. Test Vectors

#### Mnemonic

```
test test test test test test test test test test test junk
```

#### BIP-44 Labeled Accounts

**Profile 0 ("Personal"):**

| Path | Address | Label (example) |
|------|---------|-----------------|
| `m/44'/60'/0'/0/0` | `0xf39F...2266` | "Primary Wallet" |
| `m/44'/60'/0'/0/1` | `0x7099...79C8` | "DeFi Operations" |

**Profile 1 ("Work") — completely separate:**

| Path | Address | Label (example) |
|------|---------|-----------------|
| `m/44'/60'/1'/0/0` | `0x3C44...93e7` | "Company Operations" |

#### Delegation Keys

Given external address `0xdead000000000000000000000000000000000000` within Identity 0:

```
Address bytes: [0xde, 0xad, 0x00, 0x00, 0x00, ...]

Chunks (4 bytes each, big-endian):
  [0xdead0000, 0x00000000, 0x00000000, 0x00000000, 0x00000000]

As uint32:
  [3735879680, 0, 0, 0, 0]

Hardened indices (add 2³¹):
  [3735879680', 0', 0', 0', 0']

Identity 0 path: m/44'/60'/0'/1/3735879680'/0'/0'/0'/0'
Identity 1 path: m/44'/60'/1'/1/3735879680'/0'/0'/0'/0'  (different key!)
```

The same external address produces different delegation keys per identity, ensuring isolation.

### 10. References

- [NXP-1: Identity Model](/specs/nxp-1-identity-model)
- [Appendix I: System Key Registry](/specs/appendix-i-system-key-registry)
- [BIP-32: Hierarchical Deterministic Wallets](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
- [BIP-43: Purpose Field for Deterministic Wallets](https://github.com/bitcoin/bips/blob/master/bip-0043.mediawiki)
- [BIP-44: Multi-Account Hierarchy for Deterministic Wallets](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki)
- [EIP-1581: Non-wallet usage of keys derived from BIP-32 trees](https://eips.ethereum.org/EIPS/eip-1581)
- [EIP-7702: Set EOA account code](https://eips.ethereum.org/EIPS/eip-7702)
- [Status Keycard](https://github.com/status-im/status-keycard) — 10-node depth limit (`KEY_PATH_MAX_DEPTH = 10`)
- [SLIP-44: Registered coin types](https://github.com/satoshilabs/slips/blob/master/slip-0044.md)

## Changelog

### Version 1.0.0 (2025-12-08)

- Initial NXP-2 specification
- Define BIP-44 derivation with metadata-based account organization
- Specify identity-scoped delegation key derivation from external addresses
- Define index space partitioning for user and system accounts
- Document Keycard integration and 10-level depth compatibility
- Specify authorization states (pending and active) for delegation keys

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
