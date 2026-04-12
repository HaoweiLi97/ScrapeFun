# Remote Auth Server API Contract

This document defines the API expected by ScrapeFun server when `LICENSE_SERVER_URL` is configured.

When ScrapeFun runs with `LICENSE_MODE=hybrid`, remote auth remains the source of truth, but ScrapeFun may temporarily allow local short-term authorization if this API is unavailable.

Hybrid fallback behavior implemented in ScrapeFun server:
- Seat checks can fall back to a short-lived local snapshot.
- Session handling can only reuse cached remote session tokens for the same device (no local token minting).
- Once local grace expires, remote connectivity is required again.

## Common

- Base URL: `${LICENSE_SERVER_URL}`
- Content type: `application/json`
- Runtime endpoint required headers:
  - `X-License-Instance-Id`: self-hosted instance id
  - `X-License-Client`: `scrapetab-server`
  - `X-License-Api-Key`: runtime key for this instance (not master admin key)
  - `X-License-Installation-Id`: current installation id (required after first activation)
- Install exchange endpoint body:
  - `installToken`: one-time or low-usage installation token
- Admin endpoint required headers:
  - `X-License-Api-Key`: master admin key

All `/v1/licenses/*` responses should be signed:
- `X-License-Signature-Alg`: `ed25519`
- `X-License-Signature-Ts`: unix ms timestamp used in signature
- `X-License-Signature`: base64url signature over `${X-License-Signature-Ts}.${rawJsonBody}`

ScrapeFun server verifies signatures with `LICENSE_SERVER_PUBLIC_KEY_B64`.

All error responses should include:

```json
{
  "error": "human readable message",
  "code": "MACHINE_READABLE_CODE"
}
```

## Data Shape

### `PremiumStatus`

```json
{
  "licenseRequired": true,
  "licensed": true,
  "activatedAt": "2026-03-02T12:00:00.000Z",
  "tier": "pro",
  "expiresAt": null,
  "maxDevices": 1,
  "deviceCount": 1
}
```

### `InstallationLease`

Signed token string issued by license-server and stored by ScrapeFun for offline premium authorization. The token payload includes:

- `uid`
- `iid` (instance id)
- `ins` (installation id)
- `maxDevices`
- `activatedAt`
- `iat`
- `exp`

### `Device`

```json
{
  "id": "device-001",
  "name": "Infuse on iPhone",
  "boundAt": "2026-03-02T12:00:00.000Z",
  "lastSeenAt": "2026-03-02T12:30:00.000Z"
}
```

## Endpoints

### 1) Install Token Exchange

- `POST /v1/licenses/install/exchange`
- Body:

```json
{
  "installToken": "stinst_xxx",
  "requestedInstallationId": "instl_xxx"
}
```

- Success response:

```json
{
  "instanceId": "inst_xxx",
  "apiKey": "stlic_xxx",
  "notes": "customer A",
  "usedCount": 1,
  "maxActivations": 1
}
```

- Failure codes:
  - `INSTALL_TOKEN_REQUIRED`
  - `INSTALL_TOKEN_INVALID`
  - `INSTALL_TOKEN_EXPIRED`
  - `INSTALL_TOKEN_ALREADY_USED`
  - `INSTALL_TOKEN_REBIND_REQUIRED`

### 2) User Status

- `GET /v1/licenses/users/:userId/status`
- Response: `PremiumStatus` or `{ "status": PremiumStatus }`

### 3) User Devices

- `GET /v1/licenses/users/:userId/devices`
- Response: `{ "devices": Device[] }` or `Device[]`

### 4) Seat Check / Auto Bind

- `POST /v1/licenses/users/:userId/seats/check`
- Body:

```json
{
  "deviceId": "device-001",
  "deviceName": "Infuse iPhone",
  "requireDevice": true,
  "autoBind": true
}
```

- Success response:

```json
{
  "ok": true,
  "status": { "...": "PremiumStatus" },
  "deviceId": "device-001",
  "devices": [],
  "autoBound": true
}
```

- Failure response:

```json
{
  "ok": false,
  "code": "PREMIUM_PLAN_REQUIRED | DEVICE_ID_REQUIRED | DEVICE_SEAT_LIMIT",
  "error": "reason",
  "status": { "...": "PremiumStatus" },
  "devices": []
}
```

### 5) Unbind Device

- `DELETE /v1/licenses/users/:userId/devices/:deviceId`
- Response: `{ "devices": Device[] }` or `Device[]`
- Possible throttle response:

```json
{
  "error": "Rebind cooldown active. Try again after 2026-03-06T12:00:00.000Z",
  "code": "LICENSE_REBIND_COOLDOWN",
  "retryAfterMs": 123456,
  "nextRebindAllowedAt": "2026-03-06T12:00:00.000Z"
}
```

### 6) Activate by License Key

- `POST /v1/licenses/activate`
- Public first activation does not require pre-issued runtime credentials.
- If `X-License-Instance-Id` is present, the caller is treated as an existing instance and should also provide a valid runtime API key.
- Body:

```json
{
  "licenseKey": "XXXX-XXXX-XXXX",
  "userId": "user-123",
  "installationId": "instl_xxx",
  "installationNonce": "optional-first-activation-nonce"
}
```

- Success:

```json
{
  "status": { "...": "PremiumStatus" },
  "installationLease": "...",
  "installationId": "instl_xxx",
  "leaseExpiresAt": "...",
  "runtimeInstanceId": "inst_xxx",
  "runtimeApiKey": "stlic_xxx"
}
```
- Failure codes:
  - `LICENSE_NOT_CONFIGURED`
  - `LICENSE_KEY_REQUIRED`
  - `LICENSE_KEY_INVALID`
  - `LICENSE_KEY_ALREADY_USED`
  - `LICENSE_KEY_BOUND_DEVICE`
  - `LICENSE_REBIND_COOLDOWN`
  - `INSTALLATION_REBIND_REQUIRED`
  - `INSTALLATION_ID_REQUIRED`
  - `USER_ID_REQUIRED`

### 7) Session Token Issue

- `POST /v1/licenses/session/issue`
- Body:

```json
{
  "userId": "user-123",
  "deviceId": "device-001",
  "deviceName": "Infuse iPhone"
}
```

- Success response:

```json
{
  "success": true,
  "token": "signed-token",
  "expiresAt": "2026-03-02T18:00:00.000Z",
  "status": { "...": "PremiumStatus" },
  "deviceId": "device-001",
  "payload": {
    "v": 1,
    "uid": "user-123",
    "did": "device-001",
    "tier": "pro",
    "iat": 1700000000000,
    "exp": 1700003600000
  }
}
```

- `token`, `expiresAt`, `deviceId` are required.
- `payload` is optional but recommended (used for richer local fallback metadata).

- Failure response:

```json
{
  "success": false,
  "code": "PREMIUM_PLAN_REQUIRED | DEVICE_ID_REQUIRED | DEVICE_SEAT_LIMIT",
  "error": "reason",
  "status": { "...": "PremiumStatus" }
}
```

### 6.5) Renew Installation Lease

- `POST /v1/licenses/installation/renew`
- Body:

```json
{
  "userId": "user-123",
  "installationId": "instl_xxx"
}
```

- Success:

```json
{
  "status": { "...": "PremiumStatus" },
  "installationLease": "signed-token",
  "installationId": "instl_xxx",
  "leaseExpiresAt": "2026-03-02T18:00:00.000Z"
}
```

### 7) Session Token Verify

- `POST /v1/licenses/session/verify`
- Body:

```json
{
  "token": "signed-token"
}
```

- Success response:

```json
{
  "valid": true,
  "payload": {
    "v": 1,
    "uid": "user-123",
    "did": "device-001",
    "tier": "pro",
    "iat": 1700000000000,
    "exp": 1700003600000
  }
}
```

### 8) Admin Grant Pro

- `POST /v1/licenses/users/:userId/grant`
- Body:

```json
{
  "tier": "pro",
  "source": "admin_grant",
  "maxDevices": 1,
  "expiresAt": null
}
```

- Response: `PremiumStatus` or `{ "status": PremiumStatus }`

### 9) Admin Revoke

- `POST /v1/licenses/users/:userId/revoke`
- Response: `PremiumStatus` or `{ "status": PremiumStatus }`

### 10) Admin Create or Rotate Instance Credential

- `POST /v1/licenses/admin/instances`
- Body:

```json
{
  "instanceId": "customer-instance-001",
  "notes": "optional notes"
}
```

- Response:

```json
{
  "instanceId": "customer-instance-001",
  "apiKey": "stlic_xxx",
  "status": "active",
  "notes": "optional notes"
}
```

`apiKey` should only be returned in plaintext at creation/rotation time.

### 11) Admin List Instance Credentials

- `GET /v1/licenses/admin/instances`
- Response includes metadata only (never return stored hash).

### 12) Admin Revoke Instance Credential

- `POST /v1/licenses/admin/instances/:instanceId/revoke`
- Response:

```json
{
  "success": true,
  "instanceId": "customer-instance-001",
  "status": "revoked"
}
```

### 13) Admin Get Signing Public Key

- `GET /v1/licenses/admin/signing/public-key`
- Response:

```json
{
  "algorithm": "ed25519",
  "publicKeyB64": "SPKI_DER_BASE64"
}
```
