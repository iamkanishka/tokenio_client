defmodule TokenioClient.Webhooks do
  @moduledoc """
  Token.io Webhooks API.

  Provides two capabilities:

  1. **Config management** — register, retrieve, and delete your webhook endpoint
  2. **Secure event parsing** — verify HMAC-SHA256 signatures and decode typed events

  ## Signature format

  Token.io signs deliveries with HMAC-SHA256. The `X-Token-Signature` header format is:

      t={unix_timestamp},v1={hex_digest}

  Payloads older than 5 minutes are rejected (replay protection).

  ## Phoenix/Plug example

      def webhook(conn, _params) do
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        sig = conn |> Plug.Conn.get_req_header("x-token-signature") |> List.first()
        secret = System.fetch_env!("TOKENIO_WEBHOOK_SECRET")

        case TokenioClient.Webhooks.parse(body, sig, webhook_secret: secret) do
          {:ok, %{type: "payment.completed"} = event} ->
            handle_payment(event)
            send_resp(conn, 200, "ok")

          {:error, :invalid_signature} ->
            conn |> send_resp(conn, 401, "Unauthorized") |> halt()
        end
      end
  """

  alias TokenioClient.Client
  alias TokenioClient.Error
  alias TokenioClient.HTTP.Client, as: HTTP

  @stale_threshold_s 300

  # ---------------------------------------------------------------------------
  # Config management
  # ---------------------------------------------------------------------------

  @doc """
  Register or update the webhook endpoint.

  ### Options
  - `:events` — list of event type strings to subscribe to (omit for all events)
  """
  @spec set_config(Client.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def set_config(%Client{http: http}, url, opts \\ []) do
    config = %{"url" => url}

    config =
      case opts[:events] do
        nil -> config
        events -> Map.put(config, "events", events)
      end

    with {:ok, _} <- HTTP.put(http, "/webhook-config", %{"config" => config}) do
      :ok
    end
  end

  @doc "Retrieve the current webhook configuration."
  @spec get_config(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_config(%Client{http: http}) do
    with {:ok, resp} <- HTTP.get(http, "/webhook-config") do
      {:ok, resp["config"] || %{}}
    end
  end

  @doc "Delete the webhook configuration."
  @spec delete_config(Client.t()) :: :ok | {:error, Error.t()}
  def delete_config(%Client{http: http}) do
    with {:ok, _} <- HTTP.delete(http, "/webhook-config") do
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Event parsing
  # ---------------------------------------------------------------------------

  @doc """
  Parse and verify an incoming webhook payload.

  ### Options
  - `:webhook_secret` — HMAC secret for signature verification.
    Pass `nil` or omit to skip verification (development only).

  ### Returns
  - `{:ok, event}` — event map with `:id`, `:type`, `:created_at`, `:data`, `:raw`
  - `{:error, :invalid_signature}`
  - `{:error, :stale_timestamp}`
  - `{:error, :malformed_signature}`
  - `{:error, :json_decode_error}`
  """
  @type parse_error ::
          :invalid_signature | :stale_timestamp | :malformed_signature | :json_decode_error

  @spec parse(binary(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, parse_error()}
  def parse(payload, signature, opts \\ []) do
    secret = opts[:webhook_secret]

    with :ok <- verify_signature(payload, signature, secret) do
      decode_event(payload)
    end
  end

  # ---------------------------------------------------------------------------
  # Typed event decoders
  # ---------------------------------------------------------------------------

  @doc "Decode the `data` field of a payment event."
  @spec decode_payment_data(map()) ::
          %{payment_id: String.t() | nil, status: String.t() | nil, member_id: String.t() | nil}
  def decode_payment_data(%{"data" => data}) when is_map(data) do
    %{payment_id: data["paymentId"], status: data["status"], member_id: data["memberId"]}
  end

  @doc "Decode the `data` field of a VRP consent event."
  @spec decode_vrp_consent_data(map()) ::
          %{consent_id: String.t() | nil, status: String.t() | nil}
  def decode_vrp_consent_data(%{"data" => data}) when is_map(data) do
    %{consent_id: data["consentId"], status: data["status"]}
  end

  @doc "Decode the `data` field of a VRP payment event."
  @spec decode_vrp_data(map()) ::
          %{vrp_id: String.t() | nil, consent_id: String.t() | nil, status: String.t() | nil}
  def decode_vrp_data(%{"data" => data}) when is_map(data) do
    %{vrp_id: data["vrpId"], consent_id: data["consentId"], status: data["status"]}
  end

  @doc "Decode the `data` field of a refund event."
  @spec decode_refund_data(map()) ::
          %{refund_id: String.t() | nil, transfer_id: String.t() | nil, status: String.t() | nil}
  def decode_refund_data(%{"data" => data}) when is_map(data) do
    %{refund_id: data["refundId"], transfer_id: data["transferId"], status: data["status"]}
  end

  @doc "Decode the `data` field of a payout event."
  @spec decode_payout_data(map()) ::
          %{payout_id: String.t() | nil, status: String.t() | nil}
  def decode_payout_data(%{"data" => data}) when is_map(data) do
    %{payout_id: data["payoutId"], status: data["status"]}
  end

  # ---------------------------------------------------------------------------
  # Event type constants
  # ---------------------------------------------------------------------------

  @doc "Payment event type strings."
  @spec payment_event_types() :: [String.t()]
  def payment_event_types do
    ~w[payment.created payment.updated payment.completed payment.failed payment.cancelled]
  end

  @doc "VRP consent event type strings."
  @spec vrp_consent_event_types() :: [String.t()]
  def vrp_consent_event_types do
    ~w[vrp_consent.created vrp_consent.updated vrp_consent.revoked]
  end

  @doc "VRP payment event type strings."
  @spec vrp_event_types() :: [String.t()]
  def vrp_event_types do
    ~w[vrp.created vrp.updated vrp.completed vrp.failed]
  end

  @doc "Refund event type strings."
  @spec refund_event_types() :: [String.t()]
  def refund_event_types do
    ~w[refund.created refund.updated refund.completed refund.failed]
  end

  @doc "Payout event type strings."
  @spec payout_event_types() :: [String.t()]
  def payout_event_types do
    ~w[payout.created payout.updated payout.completed payout.failed]
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  @spec verify_signature(binary(), String.t() | nil, String.t() | nil) ::
          :ok | {:error, :invalid_signature | :stale_timestamp | :malformed_signature}
  defp verify_signature(_payload, _sig, nil), do: :ok
  defp verify_signature(_payload, _sig, ""), do: :ok

  defp verify_signature(payload, signature, secret) do
    with {:ok, ts, sig_hex} <- parse_sig_header(signature),
         :ok <- check_timestamp(ts) do
      signed = Integer.to_string(ts) <> "." <> payload
      expected = Base.encode16(:crypto.mac(:hmac, :sha256, secret, signed), case: :lower)

      if secure_compare(sig_hex, expected) do
        :ok
      else
        {:error, :invalid_signature}
      end
    end
  end

  @spec parse_sig_header(String.t() | nil) ::
          {:ok, integer(), String.t()} | {:error, :malformed_signature}
  defp parse_sig_header(nil), do: {:error, :malformed_signature}
  defp parse_sig_header(""), do: {:error, :malformed_signature}

  defp parse_sig_header(header) do
    case String.split(header, ",", parts: 2) do
      ["t=" <> ts_str, "v1=" <> sig_hex] ->
        case Integer.parse(ts_str) do
          {ts, ""} -> {:ok, ts, sig_hex}
          _ -> {:error, :malformed_signature}
        end

      _ ->
        {:error, :malformed_signature}
    end
  end

  @spec check_timestamp(integer()) :: :ok | {:error, :stale_timestamp}
  defp check_timestamp(ts) do
    age = System.os_time(:second) - ts

    if age > @stale_threshold_s or age < -60 do
      {:error, :stale_timestamp}
    else
      :ok
    end
  end

  @spec decode_event(binary()) ::
          {:ok, %{optional(atom()) => term()}} | {:error, :json_decode_error}
  defp decode_event(payload) do
    case Jason.decode(payload) do
      {:ok, m} when is_map(m) ->
        event = %{
          id: m["id"],
          type: m["type"],
          api_version: m["apiVersion"],
          created_at: parse_dt(m["createdAt"]),
          data: m["data"] || %{},
          raw: m
        }

        {:ok, event}

      _ ->
        {:error, :json_decode_error}
    end
  end

  # Constant-time comparison to prevent timing side-channel attacks.
  @spec secure_compare(String.t(), String.t()) :: boolean()
  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    left = :crypto.hash(:sha256, a)
    right = :crypto.hash(:sha256, b)
    left == right
  end

  defp secure_compare(_, _), do: false

  @spec parse_dt(String.t() | nil) :: DateTime.t() | nil
  defp parse_dt(nil), do: nil

  defp parse_dt(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
