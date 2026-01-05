+++
title = "NXP-6: Communication Protocol"
date = "2025-12-24"
weight = 6
slug = "nxp-6-communication-protocol"
description = "Hierarchical multiplexing protocol for WebTransport-based communication between the Nexum browser extension and standalone application, using Cap'n Proto encoding with three-level stream hierarchy for zero-ID request correlation"

[taxonomies]
tags=["specification", "protocol", "webtransport", "capnproto", "multiplexing", "NXP"]

[extra]
author = "mfw78"
+++

## Abstract

This specification defines the communication protocol between the Nexum browser extension and standalone application. The protocol uses WebTransport with a three-level hierarchical multiplexing strategy (session, tab streams, request streams) that eliminates explicit request ID management. All messages are encoded using Cap'n Proto for efficiency and type safety. The protocol integrates with [NXP-1](/specs/nxp-1-identity-model) for identity-scoped connections and provides natural state isolation per browser tab.

## Motivation

Traditional WebSocket-based RPC protocols require explicit request/response correlation using unique identifiers. This adds complexity to message handling, state management, and error recovery. WebTransport's native stream multiplexing capabilities eliminate this overhead while providing:

1. **Zero ID Management:** Streams themselves serve as correlation mechanism
2. **Tab State Isolation:** Each browser tab maintains independent context
3. **Clean Lifecycle:** Automatic cleanup when tabs close
4. **Natural Concurrency:** Multiple concurrent requests per tab without blocking
5. **Identity Binding:** Per-tab identity context as required by [NXP-1 §4.4](/specs/nxp-1-identity-model#44-connection-binding)

### Current Protocol Limitations

The existing protocol uses `ProtocolMessage` with explicit request IDs:

```rust
struct RequestWithId {
    id: String,
    method: String,
    params: Option<Vec<Value>>,
}
```

This requires:
- ID generation and tracking on both sides
- Request/response matching logic
- Cleanup of stale request state
- Complex error handling for orphaned requests

The hierarchical stream approach eliminates all of these concerns.

## Specification

### 1. Architecture Overview

#### 1.1 Three-Level Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│ Level 1: WebTransport Session                              │
│   - Persistent connection: Extension ↔ Application         │
│   - Handles connection lifecycle, reconnection             │
│   - Certificate verification, security handshake           │
└─────────────┬───────────────────────────────────────────────┘
              │
         ┌────┴────┬────────┬────────┐
         ▼         ▼        ▼        ▼
┌──────────────────────────────────────────────────────────────┐
│ Level 2: Tab Streams (Persistent Bidirectional)             │
│   - One per browser tab                                     │
│   - Carries tab state: identity, chain, origin              │
│   - Remains open for lifetime of tab                        │
│   - Identity-bound per NXP-1 §4.4                           │
└─────────────┬────────────────────────────────────────────────┘
              │
         ┌────┴────┬────────┬────────┐
         ▼         ▼        ▼        ▼
┌──────────────────────────────────────────────────────────────┐
│ Level 3: Request Streams (Ephemeral Bidirectional)          │
│   - One per RPC call                                        │
│   - Short-lived: open, send request, receive response, close│
│   - Inherits context from parent tab stream                 │
└──────────────────────────────────────────────────────────────┘
```

#### 1.2 Stream Types

| Stream Type | Direction | Lifetime | Purpose |
|-------------|-----------|----------|---------|
| Session | Bidirectional | Connection duration | Transport layer |
| Tab Stream | Bidirectional | Tab lifetime | State container, identity binding |
| Request Stream | Bidirectional | Single RPC call | Request/response pair |

### 2. Message Encoding

All messages use [Cap'n Proto](https://capnproto.org/) binary encoding for:
- Zero-copy deserialization
- Strong typing with schema evolution
- Compact wire format
- Cross-language compatibility

#### 2.1 Schema Organization

```capnp
@0xnexum0001; # File ID

# Root message wrapper
struct Message {
  union {
    tabMessage @0 :TabMessage;
    request @1 :Request;
    response @2 :Response;
  }
}
```

#### 2.2 Tab Stream Messages

```capnp
struct TabMessage {
  union {
    initialize @0 :InitializeTab;
    initialized @1 :TabInitialized;
    setIdentity @2 :SetIdentity;
    identityChanged @3 :IdentityChanged;
    setChain @4 :SetChain;
    chainChanged @5 :ChainChanged;
    keepAlive @6 :KeepAlive;
    keepAliveAck @7 :KeepAliveAck;
    close @8 :CloseTab;
    error @9 :TabError;
  }
}

struct InitializeTab {
  tabId @0 :Data;          # UUID bytes
  origin @1 :Text;         # e.g., "https://uniswap.org"
  identity @2 :Text;       # Optional: requested identity
  chainId @3 :UInt64;      # Optional: requested chain (0 = default)
}

struct TabInitialized {
  identity @0 :Text;       # Assigned identity
  chainId @1 :UInt64;      # Assigned chain
  permissions @2 :Permissions;
}

struct SetIdentity {
  identity @0 :Text;
}

struct IdentityChanged {
  identity @0 :Text;
  requiresReconnect @1 :Bool;
}

struct SetChain {
  chainId @0 :UInt64;
}

struct ChainChanged {
  chainId @0 :UInt64;
}

struct KeepAlive {
  timestamp @0 :UInt64;    # Unix timestamp ms
}

struct KeepAliveAck {
  timestamp @0 :UInt64;
}

struct CloseTab {
  reason @0 :CloseReason;
}

enum CloseReason {
  userClosed @0;
  navigation @1;
  crash @2;
  identitySwitch @3;
}

struct TabError {
  code @0 :Int32;
  message @1 :Text;
}

struct Permissions {
  allowedMethods @0 :List(Text);
  deniedMethods @1 :List(Text);
  canRequestIdentityChange @2 :Bool;
  canRequestChainChange @3 :Bool;
  autoApproveThreshold @4 :Data;  # Optional: U256 as bytes
}
```

#### 2.3 Request Stream Messages

```capnp
struct Request {
  tabId @0 :Data;          # Links to parent tab stream
  method @1 :Text;         # JSON-RPC method name
  params @2 :Data;         # JSON-encoded parameters
}

struct Response {
  union {
    result @0 :Data;       # JSON-encoded result
    error @1 :RpcError;
  }
}

struct RpcError {
  code @0 :Int32;          # JSON-RPC error code
  message @1 :Text;
  data @2 :Data;           # Optional: JSON-encoded error data
}
```

### 3. Session Layer (Level 1)

#### 3.1 Connection Establishment

The extension initiates a WebTransport connection to the application:

```
Extension                              Application
    |                                      |
    |-------- QUIC Handshake ------------->|
    |<------- Server Certificate ----------|
    |-------- Verify Certificate --------->|
    |<------- Connection Established ------|
    |                                      |
```

**Connection URL:** `https://127.0.0.1:1250`

#### 3.2 Certificate Pinning

The application serves a self-signed certificate. The extension MUST verify:

1. Certificate hash matches expected value embedded at build time
2. Certificate is not expired
3. Connection is to localhost (127.0.0.1)

**Security Requirements:**
- Certificate hash MUST be embedded in extension at build time
- No user override for certificate validation
- Connection MUST be refused on mismatch

#### 3.3 Session State Machine

```
                    ┌─────────────┐
                    │ Disconnected│
                    └──────┬──────┘
                           │ connect()
                           ▼
                    ┌─────────────┐
              ┌─────│ Connecting  │─────┐
              │     └──────┬──────┘     │
              │            │            │
        timeout│     success│      error│
              │            ▼            │
              │     ┌─────────────┐     │
              │     │  Connected  │     │
              │     └──────┬──────┘     │
              │            │            │
              │   disconnect/error      │
              │            │            │
              ▼            ▼            ▼
           ┌──────────────────────────────┐
           │        Reconnecting          │
           │  (exponential backoff)       │
           └──────────────┬───────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
        max retries              success
              ▼                       ▼
       ┌─────────────┐         ┌─────────────┐
       │   Failed    │         │  Connected  │
       └─────────────┘         └─────────────┘
```

#### 3.4 Reconnection Strategy

On disconnection:

1. Close all tab streams and pending request streams
2. Notify all tabs of disconnection
3. Wait with exponential backoff: 1s, 2s, 4s, 8s, max 30s
4. Attempt reconnection
5. On success, recreate tab streams for active tabs
6. Notify user if reconnection fails after 5 attempts

#### 3.5 Keep-Alive

- Send keep-alive datagrams every 30 seconds
- If no response received for 90 seconds, consider connection dead
- Initiate reconnection procedure

### 4. Tab Stream Layer (Level 2)

#### 4.1 Tab Stream State Machine

```
┌────────────────┐
│   Tab Opened   │
└───────┬────────┘
        │
        ▼
┌────────────────┐     InitializeTab
│   Opening      │─────────────────────►
└───────┬────────┘
        │ TabInitialized
        ▼
┌────────────────┐
│    Active      │◄────────────────────┐
└───────┬────────┘                     │
        │                              │
   ┌────┴────┬─────────┐               │
   │         │         │               │
SetIdentity SetChain  RPC calls        │
   │         │         │               │
   ▼         ▼         ▼               │
┌─────────────────────────────┐        │
│  Processing State Change    │────────┘
└─────────────────────────────┘
        │
   Tab closed / Identity switch
        │
        ▼
┌────────────────┐     CloseTab
│   Closing      │─────────────────────►
└───────┬────────┘
        │
        ▼
┌────────────────┐
│    Closed      │
└────────────────┘
```

#### 4.2 Tab Context

The application maintains the following state per tab stream:

```rust
struct TabContext {
    /// Stream identifier (UUID)
    tab_id: TabId,

    /// Current active identity (NXP-1 identity index)
    identity: Identity,

    /// Current active chain
    chain_id: ChainId,

    /// Origin of the dapp
    origin: String,

    /// Permissions granted to this origin for this identity
    permissions: Permissions,

    /// Last activity timestamp
    last_activity: Instant,

    /// Active request streams
    active_requests: HashSet<StreamId>,
}
```

#### 4.3 Identity Binding

Per [NXP-1 §4.4](/specs/nxp-1-identity-model#44-connection-binding), tab streams are identity-scoped:

1. Each tab stream is bound to exactly one identity
2. Identity switch requires closing the tab stream and creating a new one
3. The application MUST NOT process requests after identity switch until new stream is established
4. Request streams inherit the identity from their parent tab stream

**Identity Switch Flow:**

```
Extension                              Application
    |                                      |
    |-- SetIdentity(new_identity) -------->|
    |                                      |
    |<-- IdentityChanged(requiresReconnect=true)
    |                                      |
    |-- CloseTab(identitySwitch) --------->|
    |                                      |
    |   [Stream closed]                    |
    |                                      |
    |-- [Open new tab stream] ------------>|
    |-- InitializeTab(new_identity) ------>|
    |                                      |
    |<-- TabInitialized -------------------|
    |                                      |
```

#### 4.4 Origin Permissions

Permissions are scoped to `(origin, identity)` pairs:

```rust
struct PermissionKey {
    origin: String,
    identity: Identity,
}
```

On tab initialization:
1. Lookup stored permissions for `(origin, identity)`
2. If none exist, apply default restrictive permissions
3. Return permissions in `TabInitialized` response

### 5. Request Stream Layer (Level 3)

#### 5.1 Request Stream Lifecycle

```
┌─────────────────────┐
│ RPC Call Initiated  │
│ (from dapp)         │
└──────┬──────────────┘
       │
       ▼
┌──────────────────────────┐
│ Open Request Stream      │
│ (bidirectional)          │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Send Request             │
│ { tab_id, method, params}│
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Application routes       │
│ through security pipeline│
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Receive Response         │
│ { result } or { error }  │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Close Request Stream     │
└──────────────────────────┘
```

#### 5.2 Request Routing

When a request stream is opened:

```rust
fn route_request(stream: RequestStream) -> Result<Response> {
    // 1. Read request message
    let request: Request = stream.read()?;

    // 2. Lookup tab context
    let tab_context = tab_contexts.get(&request.tab_id)
        .ok_or(Error::TabNotFound)?;

    // 3. Verify stream belongs to correct session
    verify_session_binding(&stream, &tab_context)?;

    // 4. Build security context
    let security_context = SecurityContext {
        identity: tab_context.identity.clone(),
        chain_id: tab_context.chain_id,
        origin: tab_context.origin.clone(),
        permissions: tab_context.permissions.clone(),
        method: request.method.clone(),
        params: request.params.clone(),
    };

    // 5. Execute through security pipeline
    let result = security_pipeline.execute(security_context)?;

    // 6. Return response
    Ok(result)
}
```

#### 5.3 Security Pipeline Integration

```
Request Stream Received
  │
  ├─▶ [Layer 1: Firewall]
  │   ├─ Check origin permissions
  │   ├─ Check identity permissions
  │   ├─ Check method allowlist
  │   ├─ Rate limit check
  │   └─▶ PASS or DENY
  │
  ├─▶ [Layer 2: Risk Assessment]
  │   ├─ Analyze transaction value
  │   ├─ Check destination address
  │   ├─ Evaluate calldata complexity
  │   └─▶ Calculate risk score
  │
  ├─▶ [Layer 3: Interpretation]
  │   ├─ Parse transaction components
  │   ├─ ABI decode function
  │   └─▶ Generate human-readable text
  │
  ├─▶ [Layer 4: Signing Rules]
  │   ├─ Evaluate auto-approval conditions
  │   ├─ Check identity-specific policies
  │   └─▶ AUTO-APPROVE or REQUIRE-CONFIRMATION
  │       │
  │       └─▶ [If REQUIRE-CONFIRMATION]
  │           ├─ Display TUI prompt
  │           ├─ Show human-readable description
  │           ├─ Show risk score
  │           └─ Wait for user decision
  │
  └─▶ [Layer 5: Execution Validation]
      ├─ Validate gas limits
      ├─ Check nonce
      ├─ Verify balance
      ├─ Simulate transaction
      └─▶ Execute or reject
```

#### 5.4 Request Timeout

- Default timeout: 30 seconds
- Extension MUST close stream if no response received within timeout
- Application SHOULD cancel processing if stream is reset by extension
- Long-running operations (e.g., user confirmation) may extend timeout

### 6. Error Handling

#### 6.1 Error Codes

| Code | Name | Description |
|------|------|-------------|
| -32700 | ParseError | Invalid message encoding |
| -32600 | InvalidRequest | Invalid request structure |
| -32601 | MethodNotFound | Method does not exist |
| -32602 | InvalidParams | Invalid method parameters |
| -32603 | InternalError | Internal application error |
| -32000 | TabNotFound | Tab context not found |
| -32001 | PermissionDenied | Request not allowed |
| -32002 | UserRejected | User rejected the request |
| -32003 | IdentityMismatch | Request identity doesn't match tab |
| -32004 | ChainMismatch | Request chain doesn't match tab |
| -32005 | RateLimited | Too many requests |

#### 6.2 Stream Reset Handling

**Extension Side:**
- If stream reset by application: treat as fatal error for that request
- Return error to dapp with code -32603

**Application Side:**
- If request stream reset by extension: cancel pending operation
- Clean up resources (stop signing, release locks)
- No response needed (stream already closed)

#### 6.3 Tab Stream Disconnect

If tab stream closes unexpectedly:

**Extension:**
1. Attempt to recreate tab stream once
2. If failed, notify dapp that connection is lost
3. Queue pending requests until reconnected (max 10 seconds)
4. After timeout, reject all queued requests

**Application:**
1. Cancel all pending requests for this tab
2. Clean up tab context
3. Wait for new `InitializeTab` if tab reconnects

#### 6.4 Session Disconnect

If WebTransport session closes:

**Extension:**
1. Close all tab streams
2. Initiate reconnection (see §3.4)
3. Notify all dapps of disconnection via `disconnect` event
4. Queue requests during reconnection (max 30 seconds)

**Application:**
1. Close all tab streams
2. Cancel all pending operations
3. Clean up all tab contexts
4. Wait for new connection

### 7. Concurrency and Resource Limits

#### 7.1 Concurrent Requests

Each tab can have multiple concurrent request streams:
- Maximum 100 concurrent request streams per tab
- Maximum 50 tab streams per session
- If limit reached, queue additional requests
- Extension SHOULD implement request prioritization

#### 7.2 Priority Levels

```rust
enum RequestPriority {
    /// User-initiated signing requests
    Critical = 0,
    /// State-changing methods (eth_sendTransaction)
    High = 1,
    /// Read methods (eth_call, eth_getBalance)
    Normal = 2,
    /// Batch and subscription methods
    Low = 3,
}
```

#### 7.3 Buffer Management

| Stream Type | Send Buffer | Receive Buffer |
|-------------|-------------|----------------|
| Tab Stream | 64 KB | 64 KB |
| Request Stream | 16 KB | 16 KB |

Apply backpressure if buffers fill.

#### 7.4 Rate Limiting

Per-tab rate limits:
- 100 requests/second aggregate
- 10 requests/second for signing methods
- Burst allowance: 20 requests

### 8. Migration and Compatibility

#### 8.1 WebSocket Fallback

For browsers without WebTransport support, fall back to WebSocket:

```javascript
async function connect() {
  try {
    // Try WebTransport first
    const session = new WebTransport("https://127.0.0.1:1250");
    await session.ready;
    return new WebTransportProtocol(session);
  } catch (e) {
    // Fall back to WebSocket with explicit IDs
    const ws = new WebSocket("ws://127.0.0.1:1250");
    return new WebSocketProtocol(ws);
  }
}
```

#### 8.2 Dual-Protocol Support

Application MAY support both simultaneously:
- WebTransport on port 1250 (HTTPS/QUIC)
- WebSocket on port 1251 (HTTP upgrade)

The WebSocket protocol uses the legacy `ProtocolMessage` format with explicit request IDs.

### 9. Security Considerations

#### 9.1 Certificate Pinning

MUST pin application certificate to prevent MITM attacks on localhost. The certificate hash is embedded in the extension at build time and cannot be overridden.

#### 9.2 Origin Isolation

Each tab stream is tied to exactly one origin. Cross-origin requests MUST be rejected. Origin is validated on every request against the tab context.

#### 9.3 Identity Isolation

Per [NXP-1 §3](/specs/nxp-1-identity-model#3-identity-isolation):

- Dapps cannot enumerate identities
- Dapps cannot access other tabs' contexts
- Dapps cannot determine which identity other tabs are using
- Identity switch requires explicit user action

#### 9.4 Resource Exhaustion Protection

To prevent DoS:
- Maximum 50 tab streams per session
- Maximum 100 request streams per tab
- Maximum 64 KB message size
- Rate limiting per §7.4
- Exponential backoff on reconnection

### 10. Implementation Requirements

#### 10.1 MUST

1. Use WebTransport with certificate pinning for primary transport
2. Implement three-level stream hierarchy
3. Use Cap'n Proto for message encoding
4. Bind tab streams to exactly one identity per [NXP-1 §4.4](/specs/nxp-1-identity-model#44-connection-binding)
5. Validate origin on every request
6. Implement rate limiting
7. Close all tab streams on identity switch
8. Handle stream resets gracefully

#### 10.2 SHOULD

1. Support WebSocket fallback for legacy browsers
2. Implement request prioritization
3. Provide connection status to dapps
4. Queue requests during brief disconnections
5. Log protocol events for debugging

#### 10.3 MAY

1. Support batch requests on single stream
2. Implement subscription streams for events
3. Support request cancellation
4. Provide protocol version negotiation

## References

- [NXP-1: Identity Model](/specs/nxp-1-identity-model)
- [WebTransport Specification](https://w3c.github.io/webtransport/)
- [Cap'n Proto](https://capnproto.org/)
- [QUIC Protocol (RFC 9000)](https://datatracker.ietf.org/doc/html/rfc9000)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [EIP-1193: Ethereum Provider JavaScript API](https://eips.ethereum.org/EIPS/eip-1193)
- [GitHub Issue #89](https://github.com/nxm-rs/nexum/issues/89)

## Changelog

### Version 1.0.0 (2025-12-24)

- Initial NXP-6 specification
- Define three-level hierarchical multiplexing (session, tab, request streams)
- Specify Cap'n Proto message encoding schemas
- Document session, tab, and request stream state machines
- Define request routing and security pipeline integration
- Specify identity binding requirements per NXP-1
- Document error handling and recovery procedures
- Define concurrency limits and rate limiting
- Specify WebSocket fallback for compatibility

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
