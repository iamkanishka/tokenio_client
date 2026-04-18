defmodule Tokenio.Types do
  @moduledoc "Shared domain types used across all Token.io API modules."

  # ---------------------------------------------------------------------------

  defmodule Amount do
    @moduledoc "A monetary value with ISO 4217 currency."

    @type t :: %__MODULE__{
            value: String.t(),
            currency: String.t()
          }

    defstruct [:value, :currency]

    @doc "Build an `Amount` from a raw API response map, or return `nil`."
    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil
    def from_map(%{"value" => v, "currency" => c}), do: %__MODULE__{value: v, currency: c}
    def from_map(_), do: nil

    @doc "Encode an `Amount` to an API request map."
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{value: v, currency: c}), do: %{"value" => v, "currency" => c}
  end

  # ---------------------------------------------------------------------------

  defmodule Address do
    @moduledoc "A structured postal address."

    @type t :: %__MODULE__{
            address_line: [String.t()] | nil,
            street_name: String.t() | nil,
            building_number: String.t() | nil,
            post_code: String.t() | nil,
            town_name: String.t() | nil,
            state: String.t() | nil,
            district: String.t() | nil,
            country: String.t() | nil
          }

    defstruct [
      :address_line,
      :street_name,
      :building_number,
      :post_code,
      :town_name,
      :state,
      :district,
      :country
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) when is_map(m) do
      %__MODULE__{
        address_line: m["addressLine"],
        street_name: m["streetName"],
        building_number: m["buildingNumber"],
        post_code: m["postCode"],
        town_name: m["townName"],
        state: m["state"],
        district: m["district"],
        country: m["country"]
      }
    end
  end

  # ---------------------------------------------------------------------------

  defmodule PartyAccount do
    @moduledoc "Bank account details for a debtor or creditor."

    @type t :: %__MODULE__{
            iban: String.t() | nil,
            bic: String.t() | nil,
            account_number: String.t() | nil,
            sort_code: String.t() | nil,
            name: String.t() | nil,
            ultimate_debtor_name: String.t() | nil,
            ultimate_creditor_name: String.t() | nil,
            bank_name: String.t() | nil,
            account_verification_id: String.t() | nil,
            address: Address.t() | nil
          }

    defstruct [
      :iban,
      :bic,
      :account_number,
      :sort_code,
      :name,
      :ultimate_debtor_name,
      :ultimate_creditor_name,
      :bank_name,
      :account_verification_id,
      :address
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) when is_map(m) do
      %__MODULE__{
        iban: m["iban"],
        bic: m["bic"],
        account_number: m["accountNumber"],
        sort_code: m["sortCode"],
        name: m["name"],
        ultimate_debtor_name: m["ultimateDebtorName"],
        ultimate_creditor_name: m["ultimateCreditorName"],
        bank_name: m["bankName"],
        account_verification_id: m["accountVerificationId"],
        address: Address.from_map(m["address"])
      }
    end

    @doc "Encode a party account keyword list or map to an API request map."
    @spec to_map(keyword() | map() | nil) :: map() | nil
    def to_map(nil), do: nil

    def to_map(p) when is_list(p) do
      %{}
      |> put_if("iban", p[:iban])
      |> put_if("bic", p[:bic])
      |> put_if("accountNumber", p[:account_number])
      |> put_if("sortCode", p[:sort_code])
      |> put_if("name", p[:name])
      |> put_if("ultimateDebtorName", p[:ultimate_debtor_name])
      |> put_if("ultimateCreditorName", p[:ultimate_creditor_name])
      |> put_if("bankName", p[:bank_name])
    end

    def to_map(p) when is_map(p) do
      %{}
      |> put_if("iban", p[:iban] || p["iban"])
      |> put_if("bic", p[:bic] || p["bic"])
      |> put_if("accountNumber", p[:account_number] || p["accountNumber"])
      |> put_if("sortCode", p[:sort_code] || p["sortCode"])
      |> put_if("name", p[:name] || p["name"])
      |> put_if("ultimateDebtorName", p[:ultimate_debtor_name] || p["ultimateDebtorName"])
      |> put_if("ultimateCreditorName", p[:ultimate_creditor_name] || p["ultimateCreditorName"])
      |> put_if("bankName", p[:bank_name] || p["bankName"])
    end

    defp put_if(map, _key, nil), do: map
    defp put_if(map, _key, ""), do: map
    defp put_if(map, key, val), do: Map.put(map, key, val)
  end

  # ---------------------------------------------------------------------------

  defmodule PageInfo do
    @moduledoc "Cursor-based pagination metadata returned in list responses."

    @type t :: %__MODULE__{
            limit: non_neg_integer() | nil,
            offset: String.t() | nil,
            next_offset: String.t() | nil,
            have_more: boolean()
          }

    defstruct [:limit, :offset, :next_offset, have_more: false]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) when is_map(m) do
      %__MODULE__{
        limit: m["limit"],
        offset: m["offset"],
        next_offset: m["nextOffset"],
        have_more: m["haveMore"] == true
      }
    end
  end

  # ---------------------------------------------------------------------------

  defmodule ErrorInfo do
    @moduledoc "Extended error information embedded in API resource responses."

    @type t :: %__MODULE__{
            http_error_code: non_neg_integer() | nil,
            message: String.t() | nil,
            token_external_error: boolean(),
            token_trace_id: String.t() | nil
          }

    defstruct [:http_error_code, :message, :token_trace_id, token_external_error: false]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) when is_map(m) do
      %__MODULE__{
        http_error_code: m["httpErrorCode"],
        message: m["message"],
        token_external_error: m["tokenExternalError"] == true,
        token_trace_id: m["tokenTraceId"]
      }
    end
  end

  # ---------------------------------------------------------------------------

  defmodule EmbeddedField do
    @moduledoc "A single PSU input field required for embedded authentication."

    @type t :: %__MODULE__{
            id: String.t(),
            type: String.t(),
            display_name: String.t(),
            mandatory: boolean()
          }

    defstruct [:id, :type, :display_name, mandatory: false]

    @spec from_map(map()) :: t()
    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        type: m["type"],
        display_name: m["displayName"],
        mandatory: m["mandatory"] == true
      }
    end
  end

  # ---------------------------------------------------------------------------

  defmodule Authentication do
    @moduledoc "Redirect URL or embedded auth fields returned after initiation."

    @type t :: %__MODULE__{
            redirect_url: String.t() | nil,
            embedded_auth: [EmbeddedField.t()]
          }

    defstruct [:redirect_url, embedded_auth: []]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) when is_map(m) do
      %__MODULE__{
        redirect_url: m["redirectUrl"],
        embedded_auth: Enum.map(m["embeddedAuth"] || [], &EmbeddedField.from_map/1)
      }
    end
  end

  # ---------------------------------------------------------------------------

  defmodule RefundDetails do
    @moduledoc "Refund routing and status information attached to a payment."

    @type t :: %__MODULE__{
            refund_account: map() | nil,
            payment_refund_status: String.t() | nil,
            settled_refund_amount: Amount.t() | nil,
            remaining_refund_amount: Amount.t() | nil
          }

    defstruct [
      :refund_account,
      :payment_refund_status,
      :settled_refund_amount,
      :remaining_refund_amount
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) when is_map(m) do
      %__MODULE__{
        refund_account: m["refundAccount"],
        payment_refund_status: m["paymentRefundStatus"],
        settled_refund_amount: Amount.from_map(m["settledRefundAmount"]),
        remaining_refund_amount: Amount.from_map(m["remainingRefundAmount"])
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  @doc "Parse an ISO 8601 datetime string to a `DateTime`, or return `nil`."
  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  def parse_datetime(nil), do: nil
  def parse_datetime(""), do: nil

  def parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  @doc "Build an API amount map from a `%{value:, currency:}` map or keyword list."
  @spec encode_amount(map() | keyword() | nil) :: map() | nil
  def encode_amount(nil), do: nil
  def encode_amount(%{value: v, currency: c}), do: %{"value" => v, "currency" => c}
  def encode_amount(%{"value" => v, "currency" => c}), do: %{"value" => v, "currency" => c}

  def encode_amount(kw) when is_list(kw),
    do: %{"value" => kw[:value], "currency" => kw[:currency]}
end
