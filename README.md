# TokenioClient

[![Hex.pm](https://img.shields.io/hexpm/v/tokenio_client.svg)](https://hex.pm/packages/tokenio_client)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/tokenio_client)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Production-grade Elixir client for the [Token.io Open Banking platform](https://reference.token.io).

Covers all **16 APIs** from `reference.token.io` with full type safety, automatic OAuth2 token management, retry with jitter, telemetry, and HMAC webhook verification.

---

## Installation

```elixir
# mix.exs
def deps do
  [{:tokenio_client, "~> 1.0"}]
end
```

---

## Quick Start

```elixir
# Create a client (OAuth2)
{:ok, client} = TokenioClient.new(
  client_id: System.fetch_env!("TOKENIO_CLIENT_ID"),
  client_secret: System.fetch_env!("TOKENIO_CLIENT_SECRET")
  # environment: :sandbox  ← default
  # environment: :production
)

# Initiate a payment
{:ok, payment} = TokenioClient.Payments.initiate(client, %{
  bank_id: "ob-modelo",
  amount: %{value: "10.50", currency: "GBP"},
  creditor: %{account_number: "12345678", sort_code: "040004", name: "Acme Ltd"},
  remittance_information_primary: "Invoice INV-2024-001",
  callback_url: "https://yourapp.com/payment/return",
  return_refund_account: true
})

# Handle the auth flow
if TokenioClient.Payments.Payment.requires_redirect?(payment) do
  redirect_to(payment.redirect_url)
end

# Poll to final status (prefer webhooks in production)
{:ok, final} = TokenioClient.Payments.poll_until_final(client, payment.id,
  interval_ms: 2_000,
  timeout_ms: 60_000
)
```

---

## API Coverage

| Module | Endpoints |
|---|---|
| `TokenioClient.Payments` | `initiate`, `get`, `list`, `get_with_timeout`, `provide_embedded_auth`, `generate_qr_code`, `poll_until_final` |
| `TokenioClient.VRP` | `create_consent`, `get_consent`, `list_consents`, `revoke_consent`, `list_consent_payments`, `create_payment`, `get_payment`, `list_payments`, `confirm_funds` |
| `TokenioClient.AIS` | `list_accounts`, `get_account`, `list_balances`, `get_balance`, `list_transactions`, `get_transaction`, `list_standing_orders`, `get_standing_order` |
| `TokenioClient.Banks` | `list_v1`, `list_v2`, `list_countries` |
| `TokenioClient.Refunds` | `initiate`, `get`, `list` |
| `TokenioClient.Payouts` | `initiate`, `get`, `list` |
| `TokenioClient.Settlement` | `create_account`, `list_accounts`, `get_account`, `list_transactions`, `get_transaction`, `create_rule`, `list_rules`, `delete_rule` |
| `TokenioClient.Transfers` | `redeem`, `get`, `list` |
| `TokenioClient.Tokens` | `list`, `get`, `cancel` |
| `TokenioClient.TokenRequests` | `store`, `get`, `get_result`, `initiate_bank_auth` |
| `TokenioClient.AccountOnFile` | `create`, `get`, `delete` |
| `TokenioClient.SubTPPs` | `create`, `list`, `get`, `delete` |
| `TokenioClient.AuthKeys` | `submit`, `list`, `get`, `delete` |
| `TokenioClient.Reports` | `list_bank_statuses`, `get_bank_status` |
| `TokenioClient.Webhooks` | `set_config`, `get_config`, `delete_config`, `parse`, typed decoders |
| `TokenioClient.Verification` | `initiate` |

---

## Variable Recurring Payments (VRP)

```elixir
# 1. Create consent
{:ok, consent} = TokenioClient.VRP.create_consent(client, %{
  bank_id: "ob-modelo",
  currency: "GBP",
  creditor: %{account_number: "12345678", sort_code: "040004", name: "Acme"},
  maximum_individual_amount: "500.00",
  periodic_limits: [
    %{maximum_amount: "1000.00", period_type: "MONTH", period_alignment: "CALENDAR"}
  ],
  callback_url: "https://yourapp.com/vrp/return"
})

# 2. Redirect PSU
if TokenioClient.VRP.Consent.requires_redirect?(consent) do
  redirect_to(consent.redirect_url)
end

# 3. Check funds (optional)
{:ok, available} = TokenioClient.VRP.confirm_funds(client, consent.id, "49.99")

# 4. Initiate a payment once AUTHORIZED
{:ok, payment} = TokenioClient.VRP.create_payment(client, %{
  consent_id: consent.id,
  amount: %{value: "49.99", currency: "GBP"},
  remittance_information_primary: "Subscription Jan 2025"
})
```

---

## Account Information Services (AIS)

```elixir
{:ok, %{accounts: accounts}} = TokenioClient.AIS.list_accounts(client, limit: 50)

for account <- accounts do
  {:ok, balance} = TokenioClient.AIS.get_balance(client, account.id)
  IO.puts("#{account.display_name}: #{balance.current.value} #{balance.current.currency}")
end

{:ok, %{transactions: txns}} = TokenioClient.AIS.list_transactions(client, account.id, limit: 20)
```

---

## Webhooks

```elixir
# Register your endpoint
:ok = TokenioClient.Webhooks.set_config(client, "https://yourapp.com/webhooks/tokenio_client",
  events: ["payment.completed", "vrp.completed", "refund.completed"]
)

# In your Plug/Phoenix controller
def handle_webhook(conn) do
  {:ok, body, conn} = Plug.Conn.read_body(conn)
  sig = Plug.Conn.get_req_header(conn, "x-token-signature") |> List.first()
  secret = System.fetch_env!("TOKENIO_WEBHOOK_SECRET")

  case TokenioClient.Webhooks.parse(body, sig, webhook_secret: secret) do
    {:ok, %{type: "payment.completed"} = event} ->
      data = TokenioClient.Webhooks.decode_payment_data(event)
      handle_payment_completed(data.payment_id, data.status)
      send_resp(conn, 200, "ok")

    {:ok, %{type: "vrp.completed"} = event} ->
      data = TokenioClient.Webhooks.decode_vrp_data(event)
      handle_vrp_completed(data.vrp_id)
      send_resp(conn, 200, "ok")

    {:error, :invalid_signature} ->
      conn |> send_resp(401, "Unauthorized") |> halt()

    {:error, :stale_timestamp} ->
      conn |> send_resp(400, "Stale payload") |> halt()
  end
end
```

---

## Error Handling

All API functions return `{:ok, result}` or `{:error, %TokenioClient.Error{}}`.

```elixir
case TokenioClient.Payments.get(client, payment_id) do
  {:ok, payment} ->
    payment

  {:error, %TokenioClient.Error{code: :not_found}} ->
    nil

  {:error, %TokenioClient.Error{code: :rate_limit_exceeded, retry_after: ra}} ->
    Process.sleep((ra || 5) * 1_000)
    TokenioClient.Payments.get(client, payment_id)

  {:error, %TokenioClient.Error{} = err} ->
    Logger.error("Token.io error: #{Exception.message(err)}")
    {:error, err}
end
```

### Error predicates

```elixir
alias TokenioClient.Error

Error.not_found?(err)       # true for 404
Error.unauthorized?(err)    # true for 401
Error.rate_limited?(err)    # true for 429
Error.retryable?(err)       # true for 429, 500, 502, 503, 504
```

---

## Configuration

```elixir
{:ok, client} = TokenioClient.new(
  client_id: "...",
  client_secret: "...",
  environment: :production,        # :sandbox | :production (default: :sandbox)
  timeout: 30_000,                 # ms (default: 30_000)
  max_retries: 3,                  # default: 3
  retry_wait_min: 500,             # ms (default: 500)
  retry_wait_max: 5_000            # ms (default: 5_000)
)

# Static token (bypass OAuth2 — useful for testing)
{:ok, client} = TokenioClient.new(static_token: "Bearer xyz")

# Custom base URL (for test mocks)
{:ok, client} = TokenioClient.new(static_token: "test", base_url: "http://localhost:4000")
```

### Application config (optional)

```elixir
# config/runtime.exs
config :tokenio_client,
  pool_size: 20,
  pool_count: 2
```

---

## Telemetry

```elixir
# Attach in your application startup
:telemetry.attach_many(
  "tokenio_client-telemetry",
  [
    [:tokenio_client, :request, :start],
    [:tokenio_client, :request, :stop],
    [:tokenio_client, :request, :exception]
  ],
  &MyApp.TokenioClientTelemetry.handle_event/4,
  nil
)

defmodule MyApp.TokenioClientTelemetry do
  require Logger

  def handle_event([:tokenio_client, :request, :stop], %{duration: d}, %{method: m, path: p, status: s}, _) do
    Logger.info("[tokenio_client] #{m} #{p} → #{s} (#{d}ms)")
    :telemetry.execute([:my_app, :tokenio_client, :request], %{duration: d}, %{status: s})
  end

  def handle_event([:tokenio_client, :request, :exception], %{duration: d}, %{method: m, path: p}, _) do
    Logger.error("[tokenio_client] #{m} #{p} failed after #{d}ms")
  end

  def handle_event(_, _, _, _), do: :ok
end
```

---

## Testing

```elixir
# In your test, use a static token pointing at Bypass
setup do
  bypass = Bypass.open()
  {:ok, client} = TokenioClient.new(static_token: "test", base_url: "http://localhost:#{bypass.port}")
  {:ok, bypass: bypass, client: client}
end

test "handles payment", %{bypass: bypass, client: client} do
  Bypass.expect_once(bypass, "GET", "/v2/payments/pm:abc", fn conn ->
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(%{
      "payment" => %{"id" => "pm:abc", "status" => "INITIATION_COMPLETED",
                     "createdDateTime" => "2024-01-01T00:00:00Z"}
    }))
  end)

  assert {:ok, payment} = TokenioClient.Payments.get(client, "pm:abc")
  assert TokenioClient.Payments.Payment.completed?(payment)
end
```

---

## License

MIT — see [LICENSE](LICENSE).
