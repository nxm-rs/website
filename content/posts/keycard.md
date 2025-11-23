+++
title = "Keycard: Bringing Banking-Grade Security to Web3 Wallets"
date = "2025-05-21"
updated = "2025-05-21"
slug = "keycard"

[taxonomies]
tags=["keycard", "javacard", "iso7816"]

[extra]
author = "mfw78"
+++

## Introduction

This is the first in a four-part series on [Keycard](https://keycard.tech), a smart-card Web3 wallet implementation. This series will cover the following topics:

- **The path to banking the unbanked** (this article)
- A novel approach to hardware wallet protocol security and transaction verification
- Hierarchical accounts - organise your accounts neatly
- Cashcard - mutually authenticated off-chain transactions

## What is Keycard?

[Keycard](https://keycard.tech) is a [JavaCard](https://www.javacard.com/) smart-card Web3 wallet initially designed for [Status.IM](https://status.im) and built by a team of developers under the umbrella of [IFT](https://free.technology).
It builds on open technology standards that have been around for many years, such as [ISO 7816](https://www.iso.org/standard/67495.html) and [JavaCard](https://www.javacard.com/) - the very same standards that are powering smart cards used by giants such as Visa, Mastercard, and American Express.

In the smart-card form-factor, Keycard can be used via physical contact with a smart-card reader, or alternatively via an NFC-enabled device.
It's resilient to tampering and able to function in a wide range of environments.
It's actually a hardware *wallet*, in the sense that it can withstand the everyday harsh conditions of the real world.
It's arguably the **most resilient hardware wallet** available today - leaning on standards used by financial institutions that have been developed over many years as consumers put the technology through its paces.
Accidentally took your hardware wallet for a swim? No problem - if it's a Keycard.

## Where Keycard currently stands

[Keycard](https://keycard.tech) refers to the JavaCard Web3 wallet implementation.
It provides a protocol consisting of a secure channel, key management, and signing.
All the standards for the Keycard communication protocol are open source and [documented](https://keycard.tech/docs/).
The JavaCard applet source code is published on their [GitHub repository](https://github.com/keycard-tech/status-keycard).

There are two notable areas whereby Keycard differs significantly from other hardware wallets:

### No exporting of seed phrases

Keycard does **NOT** allow for exporting of seed phrases and only allows for exporting very select private keys under the ([EIP-1581](https://eips.ethereum.org/EIPS/eip-1581)) derivation path. This makes it a secure and convenient solution for managing Web3 accounts - you never have to write down a seedphrase and risk it falling into the wrong hands - but also presents the risk that if you lose your Keycard, access to any funds stored on accounts derived from the Keycard are lost forever.

### No physical buttons and/or screen

Keycard is a smart-card, which means it has no physical buttons and/or screen. It is therefore not possible to review transactions or confirm actions prior to signing. It's for this reason that the core developers of Keycard are working on the [Keycard Shell](https://keycard.tech/keycard-shell), a small form-factor smart-card reader that can be used to interact with the Keycard, and process Web3 transactions via QR code - with a screen to review transactions and confirm actions prior to signing.

## Future Innovations

Keycard is just getting started for mainstream adoption. Whilst its current offerings are comparable to other hardware wallets, they only scratch the surface of Keycard's full potential.

Here are three key innovations we'll explore in upcoming blog posts:

### 1. Secure channel with viewers

Keycard implements its own Secure Channel Protocol, enabling **encrypted** and **integrity protected** communication between the Keycard applet and connected applications. This feature—**not found in other hardware wallets**—can be expanded to allow:

- View-only permissions for "man in the middle" devices
- **Unbounded number of verification devices** (mobile apps, web applications, etc.)
- Ability for users to change their security posture dynamically

> **Example**: A Keycard user signing a Safe transaction containing significant funds can elect to use 3 separate devices to verify the transaction before signing, reflecting a heightened security posture for this specific high-value operation.

### 2. Account hierarchies and non-asset accounts

As a [BIP32](https://github.com/bitcoin/bips/blob/43d4a1ecec42d0d4160eafb8b7f37c14f279141b/bip-0032.mediawiki) compatible wallet, Keycard supports hierarchical deterministic wallets. We're developing an intuitive "folder and file" structure to manage accounts:

> **Example**: A user's account hierarchy:
>
> - **Personal**
>   - Savings
>   - Current
> - **Business**
>   - Accounts Payable
>   - Accounts Receivable

Benefits of this approach include:
- Automatic derivation path generation based on account names
- Client-side metadata storage with optional encryption
- Non-asset accounts for messaging ([Waku](https://waku.org)) and storage ([Swarm](https://ethswarm.org))

### 3. Unbounded TPS with mutual transactions

Keycard contains multiple applets, including **Cashcard**—a simple, permissionless signer. Our proposed enhancements will create a **mutual transaction system** addressing current limitations:

- A **smart-contract vault** stores balances of all cashcards
- Balances are also **stored on the card itself** (updated via trusted channels only)
- Cards can mutually authenticate each other before accepting transfers
- System enables **off-chain, offline transactions** without blockchain bottlenecks

This creates a comprehensive money velocity approach:
1. **Cheap, low-value** point-of-sale transactions through cashcard mutual transactions
2. **Medium-value** personal savings in PIN-protected Keycard accounts
3. **High-value** savings in smart-contract wallets with Keycard sub-accounts as signers

## Conclusion

Keycard represents an intersection between Web3 and conventional banking technology. By preserving a familiar UX, we can create a seamless transition from traditional banking to Web3. The mutual transaction system eliminates the need for frequent blockchain transactions whilst maintaining the core benefits of security and decentralisation—all abstracted away from everyday users.
