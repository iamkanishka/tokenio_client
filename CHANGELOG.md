# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-15

### Added

- **16 API modules** covering the complete Token.io Open Banking platform:
  - `Tokenio.Payments` — Payments v2 (single/future-dated, redirect/embedded/decoupled auth)
  - `Tokenio.VRP` — Variable Recurring Payments (consents, payments, fund confirmation)
  - `Tokenio.AIS` — Account Information Services (accounts, balances, transactions, standing orders)
  - `Tokenio.Banks` — Bank discovery v1 and v2
  - `Tokenio.Refunds` — Payment refund initiation and tracking
  - `Tokenio.Payouts` — Settlement account payouts
  - `Tokenio.Settlement` — Virtual accounts, rules, transactions
  - `Tokenio.Transfers` — Payments v1 token redemption
  - `Tokenio.Tokens` — Token management
  - `Tokenio.TokenRequests` — Token Request flow (legacy Payments v1 / AIS)
  - `Tokenio.AccountOnFile` — Tokenized account storage
  - `Tokenio.SubTPPs` — Sub-TPP management
  - `Tokenio.AuthKeys` — RSA/EC signing key management
  - `Tokenio.Reports` — Bank operational status
  - `Tokenio.Webhooks` — Webhook config + HMAC-SHA256 event parsing
  - `Tokenio.Verification` — Account ownership verification

- **HTTP layer** (`Tokenio.HTTP.Client`):
  - Finch-backed with connection pooling and HTTP/2
  - OAuth2 client credentials with ETS token caching
  - Static bearer token support
  - Exponential backoff retry with crypto-random jitter
  - Structured telemetry events on every request
  - Structured `Logger` output

- **Typed errors** (`Tokenio.Error`):
  - Machine-readable `:code` atoms
  - `retryable?/1`, `not_found?/1`, `unauthorized?/1`, `rate_limited?/1`
  - `retry_after` field populated from `Retry-After` header

- **Rich struct types** with status predicate helpers:
  - `Tokenio.Payments.Payment` — `final?/1`, `requires_redirect?/1`, `requires_embedded_auth?/1`, `completed?/1`, `failed?/1`
  - `Tokenio.VRP.Consent` — `final?/1`, `authorized?/1`, `requires_redirect?/1`
  - `Tokenio.VRP.Payment` — `final?/1`, `completed?/1`

- **Webhook verification** with constant-time HMAC comparison and replay protection (5-min window)

- **Telemetry integration**: `[:tokenio, :request, :start/stop/exception]`

- **Zero config** OTP application with automatic Finch supervision

- Complete **ExUnit test suite** with Bypass HTTP mocks
