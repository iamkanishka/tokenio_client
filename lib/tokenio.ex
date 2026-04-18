defmodule Tokenio do
  @moduledoc """
  Production-grade Elixir client for the Token.io Open Banking platform.

  Covers all **16 APIs** from [reference.token.io](https://reference.token.io):

  | Module | API |
  |---|---|
  | `Tokenio.Payments` | Payments v2 (PIS) — single & future-dated |
  | `Tokenio.VRP` | Variable Recurring Payments |
  | `Tokenio.AIS` | Account Information Services |
  | `Tokenio.Banks` | Bank discovery (v1 + v2) |
  | `Tokenio.Refunds` | Payment refunds |
  | `Tokenio.Payouts` | Settlement payouts |
  | `Tokenio.Settlement` | Virtual accounts, rules, transactions |
  | `Tokenio.Transfers` | Transfers (Payments v1) |
  | `Tokenio.Tokens` | Tokens management |
  | `Tokenio.TokenRequests` | Token Request legacy flow |
  | `Tokenio.AccountOnFile` | Tokenized account storage |
  | `Tokenio.SubTPPs` | Sub-TPP management |
  | `Tokenio.AuthKeys` | Signing key management |
  | `Tokenio.Reports` | Bank status reports |
  | `Tokenio.Webhooks` | Webhook config + HMAC event parsing |
  | `Tokenio.Verification` | Account ownership verification |

  ## Quick start

      {:ok, client} = Tokenio.new(
        client_id: System.fetch_env!("TOKENIO_CLIENT_ID"),
        client_secret: System.fetch_env!("TOKENIO_CLIENT_SECRET")
      )

      {:ok, payment} = Tokenio.Payments.initiate(client, %{
        bank_id: "ob-modelo",
        amount: %{value: "10.50", currency: "GBP"},
        creditor: %{account_number: "12345678", sort_code: "040004", name: "Acme Ltd"},
        remittance_information_primary: "Invoice #42",
        callback_url: "https://yourapp.com/payment/return",
        return_refund_account: true
      })

      if Tokenio.Payments.Payment.requires_redirect?(payment) do
        {:redirect, payment.redirect_url}
      end

  ## Configuration options for `new/1`

  | Option | Default | Description |
  |---|---|---|
  | `:client_id` | — | OAuth2 client ID (required unless `:static_token` given) |
  | `:client_secret` | — | OAuth2 client secret |
  | `:static_token` | `nil` | Pre-obtained bearer token (bypasses OAuth2) |
  | `:environment` | `:sandbox` | `:sandbox` or `:production` |
  | `:base_url` | auto | Override API base URL |
  | `:timeout` | `30_000` | Per-request timeout in ms |
  | `:max_retries` | `3` | Max retries on 5xx / 429 |
  | `:retry_wait_min` | `500` | Minimum retry backoff in ms |
  | `:retry_wait_max` | `5_000` | Maximum retry backoff in ms |

  ## Error handling

      case Tokenio.Payments.get(client, payment_id) do
        {:ok, payment} ->
          payment

        {:error, %Tokenio.Error{code: :not_found}} ->
          nil

        {:error, %Tokenio.Error{code: :rate_limit_exceeded, retry_after: ra}} ->
          Process.sleep((ra || 5) * 1_000)
          Tokenio.Payments.get(client, payment_id)

        {:error, %Tokenio.Error{} = err} ->
          raise err
      end

  ## Telemetry

  Every HTTP request emits:

      [:tokenio, :request, :start]     — %{system_time: integer}
      [:tokenio, :request, :stop]      — %{duration: milliseconds}
      [:tokenio, :request, :exception] — %{duration: milliseconds}

  Metadata on all events: `%{method: atom, path: string}` plus `:status` on `:stop`.
  """

  alias Tokenio.Client
  alias Tokenio.Error

  @doc """
  Create a new Token.io client.

  Returns `{:ok, client}` on success or `{:error, %Tokenio.Error{}}` on
  invalid configuration.

  ## Examples

      # OAuth2 (recommended for production)
      {:ok, client} = Tokenio.new(
        client_id: "my-client-id",
        client_secret: "my-client-secret",
        environment: :production
      )

      # Static token (useful in tests)
      {:ok, client} = Tokenio.new(static_token: "Bearer xyz")

      # Custom base URL (Bypass mock in tests)
      {:ok, client} = Tokenio.new(static_token: "test", base_url: "http://localhost:4000")
  """
  @spec new(keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def new(opts) do
    case validate_opts(opts) do
      :ok -> {:ok, Client.new(opts)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Create a new client, raising `Tokenio.Error` on invalid configuration.

  See `new/1` for available options.
  """
  @spec new!(keyword()) :: Client.t()
  def new!(opts) do
    case new(opts) do
      {:ok, client} -> client
      {:error, err} -> raise err
    end
  end

  @doc "Returns the SDK version string."
  @spec version() :: String.t()
  def version, do: "1.0.0"

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  @spec validate_opts(keyword()) :: :ok | {:error, Error.t()}
  defp validate_opts(opts) do
    has_static =
      case Keyword.get(opts, :static_token) do
        nil -> false
        "" -> false
        _ -> true
      end

    has_oauth =
      Keyword.has_key?(opts, :client_id) and
        Keyword.has_key?(opts, :client_secret)

    if has_static or has_oauth do
      :ok
    else
      {:error,
       Error.validation(
         "Tokenio.new/1 requires either :static_token or both :client_id and :client_secret"
       )}
    end
  end
end
