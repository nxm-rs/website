+++
title = "Appendix I: System Key Registry"
date = "2025-12-07"
weight = 100
slug = "appendix-i-system-key-registry"
description = "Canonical registry of system key allocations for Nexum, defining reserved indices for both BIP-44 signing keys and EIP-1581 encryption keys used by infrastructure components"

[taxonomies]
tags=["specification", "appendix", "registry", "BIP44", "EIP-1581", "signing", "encryption", "NXP"]

[extra]
author = "mfw78"
+++

## Overview

This appendix defines the canonical registry of system key allocations for Nexum, establishing reserved indices for both BIP-44 signing keys and EIP-1581 encryption keys.

This registry is referenced by:
- [NXP-1: Identity Model](/specs/nxp-1-identity-model)
- [NXP-2: Derivation Path Standards](/specs/nxp-2-derivation-path-standards)
- [NXP-3: Metadata Schema](/specs/nxp-3-metadata-schema)
- [NXP-4: Storage Architecture](/specs/nxp-4-storage-architecture)

## 1. Index Space Partitioning

System keys use a reserved index range separated from user keys:

```
SYSTEM_OFFSET = 2³⁰ = 1,073,741,824
```

| Index Range | Count | Type |
|-------------|-------|------|
| 0 to 2³⁰-1 | ~1 billion | User keys |
| 2³⁰ to 2³¹-1 | ~1 billion | System keys |

## 2. Signing Keys (BIP-44)

Signing keys are derived under the standard BIP-44 path and are **non-exportable** from secure elements like Keycard. These keys sign transactions and messages.

### 2.1 Derivation Path

```
m / 44' / 60' / identity' / 0 / (SYSTEM_OFFSET + index)
```

Where:
- `44'` — BIP-44 purpose (hardened)
- `60'` — Ethereum coin type (hardened)
- `identity'` — Identity index (hardened)
- `0` — External chain
- `SYSTEM_OFFSET + index` — System key index

### 2.2 Signing Key Registry

| Index | Offset | Purpose | Specification | Exportable |
|-------|--------|---------|---------------|------------|
| 1,073,741,824 | OFFSET+0 | Gas tank | [NXP-1 §4](/specs/nxp-1-identity-model#4-system-accounts) | No |
| 1,073,741,825 | OFFSET+1 | Swarm feed owner | [NXP-4 §1.1](/specs/nxp-4-storage-architecture#11-signing-keys) | No |
| 1,073,741,826 | OFFSET+2 | Swarm batch owner | [NXP-4 §1.1](/specs/nxp-4-storage-architecture#11-signing-keys) | No |

### 2.3 Signing Key Descriptions

**Gas Tank (OFFSET+0)**
- Holds funds for paying gas on behalf of other accounts
- Used with ERC-4337 paymasters or relayers
- Each identity has its own isolated gas tank

**Swarm Feed Owner (OFFSET+1)**
- Signs feed updates (Single Owner Chunks)
- Feed address = `keccak256(feed_id || owner_address)`
- All updates to identity feeds use this key

**Swarm Batch Owner (OFFSET+2)**
- Purchases postage batches on Swarm
- Signs postage stamps for uploaded chunks
- Address becomes immutable batch owner

## 3. Encryption Keys (EIP-1581)

Encryption keys are derived under EIP-1581 non-wallet paths and are **exportable** from secure elements. These keys are used for encryption operations where the private key material must be accessible to software.

### 3.1 Derivation Path

```
m / 43' / 60' / 1581' / key_type' / (SYSTEM_OFFSET + index)
```

Where:
- `43'` — Non-BIP-44 purpose (hardened)
- `60'` — Ethereum coin type (hardened)
- `1581'` — EIP-1581 identifier (hardened)
- `key_type'` — Key type (hardened): `0'` = symmetric, `1'` = asymmetric
- `SYSTEM_OFFSET + index` — System key index

### 3.2 Encryption Key Registry

| Index | Offset | Key Type | Purpose | Specification | Exportable |
|-------|--------|----------|---------|---------------|------------|
| 1,073,741,824 | OFFSET+0 | 1 (asymmetric) | Storage encryption base | [NXP-4 §1.2](/specs/nxp-4-storage-architecture#12-encryption-keys) | Yes |

### 3.3 Encryption Key Descriptions

**Storage Encryption Base (OFFSET+0)**
- 32-byte key for encrypting stored metadata
- Used to derive per-content encryption keys via domain separation
- Enables deterministic decryption from seed phrase

## 4. Key Derivation Examples

```python
SYSTEM_OFFSET = 1073741824  # 2³⁰

def derive_signing_key(seed: bytes, identity: int, system_index: int) -> bytes:
    """Derive a BIP-44 system signing key."""
    path = f"m/44'/60'/{identity}'/0/{SYSTEM_OFFSET + system_index}"
    return derive_path(seed, path).private_key

def derive_encryption_key(seed: bytes, key_type: int, system_index: int) -> bytes:
    """Derive an EIP-1581 system encryption key."""
    path = f"m/43'/60'/1581'/{key_type}'/{SYSTEM_OFFSET + system_index}"
    return derive_path(seed, path).private_key

# Examples
gas_tank_key = derive_signing_key(seed, identity=0, system_index=0)
feed_owner_key = derive_signing_key(seed, identity=0, system_index=1)
batch_owner_key = derive_signing_key(seed, identity=0, system_index=2)
storage_encryption_key = derive_encryption_key(seed, key_type=1, system_index=0)
```

## 5. Registration Process

New system key allocations MUST:

1. Be assigned the next available index in the appropriate registry
2. Document the purpose and owning specification
3. Specify whether the key is exportable
4. Update this appendix via a pull request

Allocations SHOULD:

1. Include rationale for why a system key is needed
2. Reference the specification that defines usage
3. Consider whether signing or encryption key type is appropriate

## 6. Security Properties

| Property | Signing Keys (BIP-44) | Encryption Keys (EIP-1581) |
|----------|----------------------|---------------------------|
| Exportable | No | Yes |
| On-card signing | Yes | No (key exported) |
| Funds at risk | Yes (if signing) | No (encryption only) |
| Compromise impact | Transaction signing | Data decryption |

### 6.1 Key Isolation

- Signing keys remain on secure elements; only signatures are exported
- Encryption keys are exported to software for cryptographic operations
- Each identity has independent system keys (hardened derivation at identity level)

### 6.2 Index Collision Prevention

The `SYSTEM_OFFSET` ensures system keys cannot collide with user keys, as users would need to create over 1 billion accounts before reaching system indices.

## References

- [NXP-1: Identity Model](/specs/nxp-1-identity-model)
- [NXP-2: Derivation Path Standards](/specs/nxp-2-derivation-path-standards)
- [NXP-3: Metadata Schema](/specs/nxp-3-metadata-schema)
- [NXP-4: Storage Architecture](/specs/nxp-4-storage-architecture)
- [BIP-32: Hierarchical Deterministic Wallets](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
- [BIP-44: Multi-Account Hierarchy](https://github.com/bitcoin/bips/blob/master/bip-0044.mediawiki)
- [EIP-1581: Non-wallet usage of keys](https://eips.ethereum.org/EIPS/eip-1581)

## Changelog

### Version 1.0.0 (2025-12-07)

- Initial appendix
- Define index space partitioning with SYSTEM_OFFSET
- Establish signing key registry (BIP-44)
- Establish encryption key registry (EIP-1581)
- Document initial allocations for gas tank, Swarm feed/batch owners, storage encryption

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
