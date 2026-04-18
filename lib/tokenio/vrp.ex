defmodule TokenioClient.VRP do
  @moduledoc """
  Token.io Variable Recurring Payments (VRP) API.

  Covers the full VRP lifecycle:

  1. Create a consent — PSU authorises a recurring payment mandate
  2. Confirm fund availability against an authorised consent
  3. Initiate individual payments under the consent
  4. List, get, and revoke consents and payments

  ## Example

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

      # 2. Redirect PSU to authorize
      if TokenioClient.VRP.Consent.requires_redirect?(consent) do
        redirect_to(consent.redirect_url)
      end

      # 3. Initiate a payment against the authorized consent
      {:ok, payment} = TokenioClient.VRP.create_payment(client, %{
        consent_id: consent.id,
        amount: %{value: "49.99", currency: "GBP"},
        remittance_information_primary: "Monthly subscription"
      })
  """

  alias TokenioClient.Client
  alias TokenioClient.Error
  alias TokenioClient.HTTP.Client, as: HTTP
  alias TokenioClient.Types
  alias TokenioClient.VRP.Consent
  alias TokenioClient.VRP.Payment

  # ---------------------------------------------------------------------------
  # Consent operations
  # ---------------------------------------------------------------------------

  @doc """
  Create a new VRP consent and begin PSU authorisation.

  ### Required fields
  - `:bank_id`
  - `:creditor` — PartyAccount map or keyword list

  ### Optional fields
  - `:currency`
  - `:scheme` — default `"OBL_SWEEPING"`
  - `:periodic_limits` — list of `%{maximum_amount:, period_type:, period_alignment:}`
  - `:maximum_individual_amount` / `:minimum_individual_amount`
  - `:maximum_occurrences`
  - `:start_date_time` / `:end_date_time` — ISO 8601 strings
  - `:callback_url` / `:callback_state`
  - `:return_refund_account`
  - `:on_behalf_of_id`
  """
  @spec create_consent(Client.t(), map()) :: {:ok, Consent.t()} | {:error, Error.t()}
  def create_consent(%Client{http: http}, params) do
    initiation =
      %{}
      |> put_if("bankId", params[:bank_id])
      |> put_if("refId", params[:ref_id])
      |> put_if("remittanceInformationPrimary", params[:remittance_information_primary])
      |> put_if("remittanceInformationSecondary", params[:remittance_information_secondary])
      |> put_if("startDateTime", params[:start_date_time])
      |> put_if("endDateTime", params[:end_date_time])
      |> put_if("onBehalfOfId", params[:on_behalf_of_id])
      |> put_if("scheme", params[:scheme])
      |> put_if("localInstrument", params[:local_instrument])
      |> put_if("debtor", Types.PartyAccount.to_map(params[:debtor]))
      |> put_if("creditor", Types.PartyAccount.to_map(params[:creditor]))
      |> put_if("currency", params[:currency])
      |> put_if("minimumIndividualAmount", params[:minimum_individual_amount])
      |> put_if("maximumIndividualAmount", params[:maximum_individual_amount])
      |> put_if("periodicLimits", encode_periodic_limits(params[:periodic_limits]))
      |> put_if("maximumOccurrences", params[:maximum_occurrences])
      |> put_if("callbackUrl", params[:callback_url])
      |> put_if("callbackState", params[:callback_state])
      |> put_bool("returnRefundAccount", params[:return_refund_account])

    body = %{"initiation" => initiation}

    with {:ok, resp} <- HTTP.post(http, "/vrp-consents", body) do
      {:ok, Consent.from_map(resp["vrpConsent"])}
    end
  end

  @doc "Retrieve a single VRP consent by ID."
  @spec get_consent(Client.t(), String.t()) :: {:ok, Consent.t()} | {:error, Error.t()}
  def get_consent(%Client{http: http}, consent_id) do
    with {:ok, resp} <- HTTP.get(http, "/vrp-consents/" <> consent_id) do
      {:ok, Consent.from_map(resp["vrpConsent"])}
    end
  end

  @doc """
  List VRP consents with optional filters.

  ### Required options
  - `:limit` — integer

  ### Optional options
  - `:offset`, `:created_after`, `:created_before`, `:on_behalf_of_id`, `:scheme`
  - `:statuses` — list of status strings
  """
  @spec list_consents(Client.t(), keyword()) ::
          {:ok, %{consents: [Consent.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_consents(%Client{http: http}, opts \\ []) do
    base_query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]},
      {"createdAfter", opts[:created_after]},
      {"createdBefore", opts[:created_before]},
      {"onBehalfOfId", opts[:on_behalf_of_id]},
      {"scheme", opts[:scheme]}
    ]

    query = append_multi(base_query, "statuses", opts[:statuses] || [])

    with {:ok, resp} <- HTTP.get(http, "/vrp-consents", query: query) do
      consents = Enum.map(resp["vrpConsents"] || [], &Consent.from_map/1)
      {:ok, %{consents: consents, page_info: Types.PageInfo.from_map(resp["pageInfo"])}}
    end
  end

  @doc "Revoke an active VRP consent."
  @spec revoke_consent(Client.t(), String.t()) :: {:ok, Consent.t()} | {:error, Error.t()}
  def revoke_consent(%Client{http: http}, consent_id) do
    with {:ok, resp} <- HTTP.delete(http, "/vrp-consents/" <> consent_id) do
      {:ok, Consent.from_map(resp["vrpConsent"])}
    end
  end

  @doc "List payments made under a specific VRP consent."
  @spec list_consent_payments(Client.t(), String.t(), keyword()) ::
          {:ok, %{payments: [Payment.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_consent_payments(%Client{http: http}, consent_id, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]}
    ]

    path = "/vrp-consents/" <> consent_id <> "/payments"

    with {:ok, resp} <- HTTP.get(http, path, query: query) do
      payments = Enum.map(resp["vrps"] || [], &Payment.from_map/1)
      {:ok, %{payments: payments, page_info: Types.PageInfo.from_map(resp["pageInfo"])}}
    end
  end

  # ---------------------------------------------------------------------------
  # VRP payment operations
  # ---------------------------------------------------------------------------

  @doc """
  Initiate a single VRP payment against an authorised consent.

  ### Required fields
  - `:consent_id`
  - `:amount` — `%{value: "49.99", currency: "GBP"}`
  """
  @spec create_payment(Client.t(), map()) :: {:ok, Payment.t()} | {:error, Error.t()}
  def create_payment(%Client{http: http}, params) do
    initiation =
      %{}
      |> put_if("consentId", params[:consent_id])
      |> put_if("refId", params[:ref_id])
      |> put_if("remittanceInformationPrimary", params[:remittance_information_primary])
      |> put_if("remittanceInformationSecondary", params[:remittance_information_secondary])
      |> put_if("amount", Types.encode_amount(params[:amount]))
      |> put_bool("confirmFunds", params[:confirm_funds])

    with {:ok, resp} <- HTTP.post(http, "/vrps", %{"initiation" => initiation}) do
      {:ok, Payment.from_map(resp["vrp"])}
    end
  end

  @doc "Retrieve a single VRP payment by ID."
  @spec get_payment(Client.t(), String.t()) :: {:ok, Payment.t()} | {:error, Error.t()}
  def get_payment(%Client{http: http}, vrp_id) do
    with {:ok, resp} <- HTTP.get(http, "/vrps/" <> vrp_id) do
      {:ok, Payment.from_map(resp["vrp"])}
    end
  end

  @doc "List VRP payments with optional filters."
  @spec list_payments(Client.t(), keyword()) ::
          {:ok, %{payments: [Payment.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_payments(%Client{http: http}, opts \\ []) do
    query =
      [
        {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
        {"offset", opts[:offset]},
        {"createdAfter", opts[:created_after]},
        {"createdBefore", opts[:created_before]},
        {"vrpConsentId", opts[:consent_id]},
        {"invertIds", if(opts[:invert_ids], do: "true")},
        {"invertStatuses", if(opts[:invert_statuses], do: "true")}
      ]
      |> append_multi("ids", opts[:ids] || [])
      |> append_multi("statuses", opts[:statuses] || [])
      |> append_multi("refIds", opts[:ref_ids] || [])

    with {:ok, resp} <- HTTP.get(http, "/vrps", query: query) do
      payments = Enum.map(resp["vrps"] || [], &Payment.from_map/1)
      {:ok, %{payments: payments, page_info: Types.PageInfo.from_map(resp["pageInfo"])}}
    end
  end

  @doc """
  Check whether sufficient funds are available for a VRP payment amount.

  Returns `{:ok, true}` or `{:ok, false}`.
  """
  @spec confirm_funds(Client.t(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def confirm_funds(%Client{http: http}, consent_id, amount) do
    path = "/vrps/" <> consent_id <> "/confirm-funds"

    with {:ok, resp} <- HTTP.get(http, path, query: [{"amount", amount}]) do
      {:ok, resp["fundsAvailable"] == true}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp put_if(map, _k, nil), do: map
  defp put_if(map, _k, ""), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)

  defp put_bool(map, _k, nil), do: map
  defp put_bool(map, _k, false), do: map
  defp put_bool(map, k, true), do: Map.put(map, k, true)

  @spec encode_periodic_limits([map()] | nil) :: [map()] | nil
  defp encode_periodic_limits(nil), do: nil
  defp encode_periodic_limits([]), do: nil

  defp encode_periodic_limits(limits) do
    Enum.map(limits, fn l ->
      %{
        "maximumAmount" => l[:maximum_amount] || l["maximumAmount"],
        "periodType" => l[:period_type] || l["periodType"],
        "periodAlignment" => l[:period_alignment] || l["periodAlignment"]
      }
    end)
  end

  defp append_multi(query, _key, []), do: query
  defp append_multi(query, key, values), do: query ++ Enum.map(values, &{key, &1})
end
