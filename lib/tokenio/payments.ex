defmodule TokenioClient.Payments do
  @moduledoc """
  Token.io Payments v2 API.

  Supports single immediate and future-dated payments across redirect,
  embedded, and decoupled PSU authentication flows.

  ## Payment status lifecycle

  | Status | Terminal? | Next action |
  |---|---|---|
  | `INITIATION_PENDING` | No | Wait |
  | `INITIATION_PENDING_REDIRECT_AUTH` | No | Redirect PSU |
  | `INITIATION_PENDING_REDIRECT_HP` | No | Redirect PSU (Hosted Pages) |
  | `INITIATION_PENDING_REDIRECT_PBL` | No | Redirect PSU (Pay-By-Link) |
  | `INITIATION_PENDING_EMBEDDED_AUTH` | No | Submit embedded auth fields |
  | `INITIATION_PENDING_DECOUPLED_AUTH` | No | Wait for bank notification |
  | `INITIATION_PROCESSING` | No | Wait |
  | `INITIATION_COMPLETED` | **Yes** | — |
  | `INITIATION_REJECTED` | **Yes** | — |
  | `INITIATION_FAILED` | **Yes** | — |
  | `INITIATION_DECLINED` | **Yes** | — |
  | `INITIATION_EXPIRED` | **Yes** | — |
  | `SETTLEMENT_IN_PROGRESS` | No | Wait |
  | `SETTLEMENT_COMPLETED` | **Yes** | — |
  | `CANCELED` | **Yes** | — |

  ## Example

      {:ok, payment} = TokenioClient.Payments.initiate(client, %{
        bank_id: "ob-modelo",
        amount: %{value: "10.50", currency: "GBP"},
        creditor: %{account_number: "12345678", sort_code: "040004", name: "Acme Ltd"},
        remittance_information_primary: "Invoice #42",
        callback_url: "https://yourapp.com/payment/return",
        return_refund_account: true
      })

      if TokenioClient.Payments.Payment.requires_redirect?(payment) do
        {:redirect, payment.redirect_url}
      end
  """

  alias TokenioClient.Client
  alias TokenioClient.Error
  alias TokenioClient.HTTP.Client, as: HTTP
  alias TokenioClient.Payments.Payment
  alias TokenioClient.Types

  @base "/v2/payments"

  # ---------------------------------------------------------------------------
  # initiate/2
  # ---------------------------------------------------------------------------

  @doc """
  Initiate a new single payment.

  ### Required fields
  - `:bank_id` — Token.io bank identifier

  ### Common optional fields
  - `:amount` — `%{value: "10.00", currency: "GBP"}` or keyword list
  - `:creditor` — map/keyword with `:account_number`, `:sort_code`, `:iban`, `:name`
  - `:debtor` — map/keyword (same keys as creditor)
  - `:remittance_information_primary`
  - `:remittance_information_secondary`
  - `:ref_id` — idempotency key
  - `:execution_date` — `"YYYY-MM-DD"` for future-dated payments
  - `:callback_url` / `:callback_state`
  - `:flow_type` — `"FULL_HOSTED_PAGES"`, `"REDIRECT"`, `"EMBEDDED"`, `"PAY_BY_LINK"`
  - `:return_refund_account` — boolean
  - `:on_behalf_of_id` — sub-TPP member ID
  - `:vrp_consent_id` — link to VRP consent
  - `:pisp_consent_accepted` — boolean
  - `:initial_embedded_auth` — `%{"field_id" => "value"}`
  """
  @spec initiate(Client.t(), map()) :: {:ok, Payment.t()} | {:error, Error.t()}
  def initiate(%Client{http: http}, params) do
    body = build_initiation_body(params)

    with {:ok, resp} <- HTTP.post(http, @base, body) do
      {:ok, Payment.from_map(resp["payment"])}
    end
  end

  # ---------------------------------------------------------------------------
  # list/2
  # ---------------------------------------------------------------------------

  @doc """
  List payments with optional filters.

  ### Required options
  - `:limit` — integer 1–200

  ### Optional options
  - `:offset` — pagination cursor
  - `:statuses` — list of status strings
  - `:ids` — list of payment IDs
  - `:ref_ids` — list of ref IDs
  - `:created_after` / `:created_before` — ISO 8601 strings
  - `:on_behalf_of_id`
  - `:vrp_consent_id`
  - `:type` — `"SINGLE_IMMEDIATE_PAYMENT"` or `"VARIABLE_RECURRING_PAYMENT"`
  - `:invert_ids` / `:invert_statuses` — boolean
  - `:external_psu_reference`
  """
  @spec list(Client.t(), keyword()) ::
          {:ok, %{payments: [Payment.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list(%Client{http: http}, opts \\ []) do
    limit = Keyword.fetch!(opts, :limit)

    cond do
      limit not in 1..200 ->
        {:error, Error.validation("limit must be between 1 and 200, got: #{limit}")}

      true ->
        query =
          [
            {"limit", Integer.to_string(limit)},
            {"offset", opts[:offset]},
            {"onBehalfOfId", opts[:on_behalf_of_id]},
            {"createdAfter", opts[:created_after]},
            {"createdBefore", opts[:created_before]},
            {"externalPsuReference", opts[:external_psu_reference]},
            {"vrpConsentId", opts[:vrp_consent_id]},
            {"type", opts[:type]},
            {"invertIds", bool_param(opts[:invert_ids])},
            {"invertStatuses", bool_param(opts[:invert_statuses])}
          ]
          |> append_multi("ids", opts[:ids] || [])
          |> append_multi("statuses", opts[:statuses] || [])
          |> append_multi("refIds", opts[:ref_ids] || [])

        with {:ok, resp} <- HTTP.get(http, @base, query: query) do
          payments = Enum.map(resp["payments"] || [], &Payment.from_map/1)
          {:ok, %{payments: payments, page_info: Types.PageInfo.from_map(resp["pageInfo"])}}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # get/2
  # ---------------------------------------------------------------------------

  @doc "Retrieve a single payment by ID."
  @spec get(Client.t(), String.t()) :: {:ok, Payment.t()} | {:error, Error.t()}
  def get(_client, ""), do: {:error, Error.validation("payment_id is required")}

  def get(%Client{http: http}, payment_id) when is_binary(payment_id) do
    with {:ok, resp} <- HTTP.get(http, @base <> "/" <> payment_id) do
      {:ok, Payment.from_map(resp["payment"])}
    end
  end

  # ---------------------------------------------------------------------------
  # get_with_timeout/3
  # ---------------------------------------------------------------------------

  @doc """
  Retrieve a payment with a server-side long-poll timeout (seconds).

  Useful for polling during redirect auth without hammering the API.
  """
  @spec get_with_timeout(Client.t(), String.t(), pos_integer()) ::
          {:ok, Payment.t()} | {:error, Error.t()}
  def get_with_timeout(%Client{http: http}, payment_id, timeout_s)
      when is_binary(payment_id) and payment_id != "" do
    extra = [{"request-timeout", Integer.to_string(timeout_s)}]

    with {:ok, resp} <- HTTP.get(http, @base <> "/" <> payment_id, extra_headers: extra) do
      {:ok, Payment.from_map(resp["payment"])}
    end
  end

  # ---------------------------------------------------------------------------
  # provide_embedded_auth/3
  # ---------------------------------------------------------------------------

  @doc """
  Submit PSU credentials for embedded authentication.

  Called when payment status is `INITIATION_PENDING_EMBEDDED_AUTH`.

      {:ok, updated} = TokenioClient.Payments.provide_embedded_auth(client, payment_id, %{
        "otp_field_id" => "123456"
      })
  """
  @spec provide_embedded_auth(Client.t(), String.t(), map()) ::
          {:ok, Payment.t()} | {:error, Error.t()}
  def provide_embedded_auth(%Client{http: http}, payment_id, auth_fields)
      when is_binary(payment_id) and payment_id != "" do
    body = %{"paymentId" => payment_id, "embeddedAuth" => auth_fields}
    path = @base <> "/" <> payment_id <> "/embedded-auth"

    with {:ok, resp} <- HTTP.post(http, path, body) do
      {:ok, Payment.from_map(resp["payment"])}
    end
  end

  # ---------------------------------------------------------------------------
  # generate_qr_code/2
  # ---------------------------------------------------------------------------

  @doc """
  Generate a 240×240 SVG QR code for the given redirect URL.

  Returns raw SVG bytes.
  """
  @spec generate_qr_code(Client.t(), String.t()) ::
          {:ok, binary()} | {:error, Error.t()}
  def generate_qr_code(%Client{http: http}, url) when is_binary(url) and url != "" do
    query = [{"data", URI.encode(url)}]

    with {:ok, body, _status} <- HTTP.get_raw(http, "/qr-code", query: query) do
      {:ok, body}
    end
  end

  # ---------------------------------------------------------------------------
  # poll_until_final/3
  # ---------------------------------------------------------------------------

  @doc """
  Poll a payment until it reaches a terminal status or `timeout_ms` elapses.

  Prefer webhooks in production. Useful for tests and simple integrations.

  ### Options
  - `:interval_ms` — polling interval in ms (default: `2_000`)
  - `:timeout_ms` — maximum wait in ms (default: `60_000`)
  """
  @spec poll_until_final(Client.t(), String.t(), keyword()) ::
          {:ok, Payment.t()} | {:error, :timeout | Error.t()}
  def poll_until_final(client, payment_id, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, 2_000)
    timeout = Keyword.get(opts, :timeout_ms, 60_000)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_poll(client, payment_id, interval, deadline)
  end

  @spec do_poll(Client.t(), String.t(), pos_integer(), integer()) ::
          {:ok, Payment.t()} | {:error, :timeout | Error.t()}
  defp do_poll(client, payment_id, interval, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      case get(client, payment_id) do
        {:ok, %Payment{} = p} ->
          if Payment.final?(p) do
            {:ok, p}
          else
            Process.sleep(interval)
            do_poll(client, payment_id, interval, deadline)
          end

        {:error, _} = err ->
          err
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec build_initiation_body(map()) :: map()
  defp build_initiation_body(params) do
    initiation =
      %{}
      |> put_if("bankId", params[:bank_id])
      |> put_if("refId", params[:ref_id])
      |> put_if("remittanceInformationPrimary", params[:remittance_information_primary])
      |> put_if("remittanceInformationSecondary", params[:remittance_information_secondary])
      |> put_if("onBehalfOfId", params[:on_behalf_of_id])
      |> put_if("vrpConsentId", params[:vrp_consent_id])
      |> put_if("amount", Types.encode_amount(params[:amount]))
      |> put_if("localInstrument", params[:local_instrument])
      |> put_if("debtor", Types.PartyAccount.to_map(params[:debtor]))
      |> put_if("creditor", Types.PartyAccount.to_map(params[:creditor]))
      |> put_if("executionDate", params[:execution_date])
      |> put_if("callbackUrl", params[:callback_url])
      |> put_if("callbackState", params[:callback_state])
      |> put_if("flowType", params[:flow_type])
      |> put_if("chargeBearer", params[:charge_bearer])
      |> put_bool("confirmFunds", params[:confirm_funds])
      |> put_bool("returnRefundAccount", params[:return_refund_account])
      |> put_bool("returnTokenizedAccount", params[:return_tokenized_account])
      |> put_bool(
        "disableFutureDatedPaymentConversion",
        params[:disable_future_dated_payment_conversion]
      )

    %{}
    |> Map.put("initiation", initiation)
    |> put_if("initialEmbeddedAuth", params[:initial_embedded_auth])
    |> put_bool("pispConsentAccepted", params[:pisp_consent_accepted])
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, _key, ""), do: map
  defp put_if(map, key, val), do: Map.put(map, key, val)

  defp put_bool(map, _key, nil), do: map
  defp put_bool(map, _key, false), do: map
  defp put_bool(map, key, true), do: Map.put(map, key, true)

  @spec bool_param(boolean() | nil) :: String.t() | nil
  defp bool_param(true), do: "true"
  defp bool_param(_), do: nil

  defp append_multi(query, _key, []), do: query
  defp append_multi(query, key, values), do: query ++ Enum.map(values, &{key, &1})
end
