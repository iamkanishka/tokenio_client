defmodule Tokenio.AIS do
  @moduledoc """
  Token.io Account Information Services (AIS) API.

  Provides read access to bank account data once a PSU has granted an AIS
  consent: accounts, balances, standing orders, and transactions.
  """

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Account do
    @moduledoc "A bank account returned from the AIS API."

    @type t :: %__MODULE__{
            id: String.t(),
            display_name: String.t() | nil,
            type: String.t() | nil,
            currency: String.t() | nil,
            bank_id: String.t() | nil,
            iban: String.t() | nil,
            account_number: String.t() | nil,
            sort_code: String.t() | nil,
            bic: String.t() | nil,
            status: String.t() | nil,
            created_at: DateTime.t() | nil,
            updated_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [
      :id,
      :display_name,
      :type,
      :currency,
      :bank_id,
      :iban,
      :account_number,
      :sort_code,
      :bic,
      :status,
      :created_at,
      :updated_at,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        display_name: m["displayName"],
        type: m["type"],
        currency: m["currency"],
        bank_id: m["bankId"],
        iban: m["iban"],
        account_number: m["accountNumber"],
        sort_code: m["sortCode"],
        bic: m["bic"],
        status: m["status"],
        created_at: Types.parse_datetime(m["createdDateTime"]),
        updated_at: Types.parse_datetime(m["updatedDateTime"]),
        raw: m
      }
    end
  end

  defmodule Balance do
    @moduledoc "Balance details for an AIS account."

    @type t :: %__MODULE__{
            account_id: String.t(),
            current: Types.Amount.t() | nil,
            available: Types.Amount.t() | nil,
            credit_limit: Types.Amount.t() | nil,
            updated_at: DateTime.t() | nil
          }

    defstruct [:account_id, :current, :available, :credit_limit, :updated_at]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        account_id: m["accountId"],
        current: Types.Amount.from_map(m["current"]),
        available: Types.Amount.from_map(m["available"]),
        credit_limit: Types.Amount.from_map(m["creditLimit"]),
        updated_at: Types.parse_datetime(m["updatedDateTime"])
      }
    end
  end

  defmodule Transaction do
    @moduledoc "An account transaction."

    @type t :: %__MODULE__{
            id: String.t(),
            account_id: String.t(),
            amount: Types.Amount.t() | nil,
            type: String.t() | nil,
            status: String.t() | nil,
            description: String.t() | nil,
            merchant_name: String.t() | nil,
            booking_date_time: DateTime.t() | nil,
            value_date_time: DateTime.t() | nil,
            raw: map()
          }

    defstruct [
      :id,
      :account_id,
      :amount,
      :type,
      :status,
      :description,
      :merchant_name,
      :booking_date_time,
      :value_date_time,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        account_id: m["accountId"],
        amount: Types.Amount.from_map(m["amount"]),
        type: m["type"],
        status: m["status"],
        description: m["description"],
        merchant_name: m["merchantName"],
        booking_date_time: Types.parse_datetime(m["bookingDateTime"]),
        value_date_time: Types.parse_datetime(m["valueDateTime"]),
        raw: m
      }
    end
  end

  defmodule StandingOrder do
    @moduledoc "A recurring payment standing order."

    @type t :: %__MODULE__{
            id: String.t(),
            account_id: String.t(),
            amount: Types.Amount.t() | nil,
            frequency: String.t() | nil,
            next_payment_date: String.t() | nil,
            status: String.t() | nil
          }

    defstruct [:id, :account_id, :amount, :frequency, :next_payment_date, :status]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        account_id: m["accountId"],
        amount: Types.Amount.from_map(m["amount"]),
        frequency: m["frequency"],
        next_payment_date: m["nextPaymentDate"],
        status: m["status"]
      }
    end
  end

  @doc "List accounts. Requires `:limit` option."
  @spec list_accounts(Client.t(), keyword()) ::
          {:ok, %{accounts: [Account.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_accounts(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/accounts", query: query) do
      {:ok,
       %{
         accounts: Enum.map(resp["accounts"] || [], &Account.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve a single account by ID."
  @spec get_account(Client.t(), String.t()) :: {:ok, Account.t()} | {:error, Error.t()}
  def get_account(%Client{http: http}, account_id) do
    with {:ok, resp} <- HTTP.get(http, "/accounts/" <> account_id) do
      {:ok, Account.from_map(resp["account"])}
    end
  end

  @doc "List balances for all accounts."
  @spec list_balances(Client.t(), keyword()) ::
          {:ok, %{balances: [Balance.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_balances(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/accounts/balances", query: query) do
      {:ok,
       %{
         balances: Enum.map(resp["balances"] || [], &Balance.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve balance for a specific account."
  @spec get_balance(Client.t(), String.t()) :: {:ok, Balance.t()} | {:error, Error.t()}
  def get_balance(%Client{http: http}, account_id) do
    with {:ok, resp} <- HTTP.get(http, "/accounts/" <> account_id <> "/balance") do
      {:ok, Balance.from_map(resp["balance"])}
    end
  end

  @doc "List transactions for an account. Requires `:limit` option."
  @spec list_transactions(Client.t(), String.t(), keyword()) ::
          {:ok, %{transactions: [Transaction.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_transactions(%Client{http: http}, account_id, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]}
    ]

    path = "/accounts/" <> account_id <> "/transactions"

    with {:ok, resp} <- HTTP.get(http, path, query: query) do
      {:ok,
       %{
         transactions: Enum.map(resp["transactions"] || [], &Transaction.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve a single transaction."
  @spec get_transaction(Client.t(), String.t(), String.t()) ::
          {:ok, Transaction.t()} | {:error, Error.t()}
  def get_transaction(%Client{http: http}, account_id, tx_id) do
    path = "/accounts/" <> account_id <> "/transactions/" <> tx_id

    with {:ok, resp} <- HTTP.get(http, path) do
      {:ok, Transaction.from_map(resp["transaction"])}
    end
  end

  @doc "List standing orders."
  @spec list_standing_orders(Client.t(), keyword()) ::
          {:ok, %{standing_orders: [StandingOrder.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_standing_orders(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/accounts/standing-orders", query: query) do
      {:ok,
       %{
         standing_orders: Enum.map(resp["standingOrders"] || [], &StandingOrder.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve a single standing order."
  @spec get_standing_order(Client.t(), String.t(), String.t()) ::
          {:ok, StandingOrder.t()} | {:error, Error.t()}
  def get_standing_order(%Client{http: http}, account_id, so_id) do
    path = "/accounts/" <> account_id <> "/standing-orders/" <> so_id

    with {:ok, resp} <- HTTP.get(http, path) do
      {:ok, StandingOrder.from_map(resp["standingOrder"])}
    end
  end
end

# =============================================================================

defmodule Tokenio.Banks do
  @moduledoc "Token.io Banks v1 and v2 APIs for listing supported financial institutions."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Bank do
    @moduledoc "A financial institution supported by Token.io."

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            display_name: String.t() | nil,
            logo_uri: String.t() | nil,
            country: String.t() | nil,
            capabilities: [String.t()],
            bic: String.t() | nil,
            provider: String.t() | nil,
            requires_callback_url: boolean(),
            open_banking_standard: String.t() | nil,
            enabled: boolean(),
            raw: map()
          }

    defstruct [
      :id,
      :name,
      :display_name,
      :logo_uri,
      :country,
      :bic,
      :provider,
      :open_banking_standard,
      capabilities: [],
      requires_callback_url: false,
      enabled: false,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        name: m["name"] || "",
        display_name: m["displayName"],
        logo_uri: m["logoUri"] || m["logo"],
        country: m["country"],
        capabilities: m["capabilities"] || [],
        bic: m["bic"],
        provider: m["provider"],
        requires_callback_url: m["requiresCallbackUrl"] == true,
        open_banking_standard: m["openBankingStandard"],
        enabled: m["enabled"] == true,
        raw: m
      }
    end
  end

  @doc "List banks using the v1 API."
  @spec list_v1(Client.t(), keyword()) ::
          {:ok, %{banks: [Bank.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_v1(%Client{http: http}, opts \\ []) do
    with {:ok, resp} <- HTTP.get(http, "/banks", query: banks_query(opts)) do
      {:ok,
       %{
         banks: Enum.map(resp["banks"] || [], &Bank.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "List banks using the v2 API."
  @spec list_v2(Client.t(), keyword()) ::
          {:ok, %{banks: [Bank.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_v2(%Client{http: http}, opts \\ []) do
    with {:ok, resp} <- HTTP.get(http, "/v2/banks", query: banks_query(opts)) do
      {:ok,
       %{
         banks: Enum.map(resp["banks"] || [], &Bank.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "List supported countries."
  @spec list_countries(Client.t()) :: {:ok, [String.t()]} | {:error, Error.t()}
  def list_countries(%Client{http: http}) do
    with {:ok, resp} <- HTTP.get(http, "/banks/countries") do
      {:ok, resp["countries"] || []}
    end
  end

  @spec banks_query(keyword()) :: [{String.t(), String.t() | nil}]
  defp banks_query(opts) do
    base = [
      {"limit", Integer.to_string(Keyword.get(opts, :limit, 50))},
      {"search", opts[:search]},
      {"country", opts[:country]},
      {"provider", opts[:provider]},
      {"sort", opts[:sort]}
    ]

    base
    |> Kernel.++(Enum.map(opts[:ids] || [], &{"ids", &1}))
    |> Kernel.++(Enum.map(opts[:capabilities] || [], &{"capabilities", &1}))
  end
end

# =============================================================================

defmodule Tokenio.Refunds do
  @moduledoc "Token.io Refunds API — initiate and track payment refunds."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Refund do
    @moduledoc "A refund resource."

    @terminal ~w[INITIATION_COMPLETED INITIATION_REJECTED INITIATION_FAILED]

    @type t :: %__MODULE__{
            id: String.t(),
            transfer_id: String.t() | nil,
            status: String.t(),
            status_reason_information: String.t() | nil,
            error_info: Types.ErrorInfo.t() | nil,
            created_at: DateTime.t() | nil,
            updated_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [
      :id,
      :transfer_id,
      :status,
      :status_reason_information,
      :error_info,
      :created_at,
      :updated_at,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        transfer_id: m["transferId"],
        status: m["status"] || "",
        status_reason_information: m["statusReasonInformation"],
        error_info: Types.ErrorInfo.from_map(m["errorInfo"]),
        created_at: Types.parse_datetime(m["createdDateTime"]),
        updated_at: Types.parse_datetime(m["updatedDateTime"]),
        raw: m
      }
    end

    @spec final?(t()) :: boolean()
    def final?(%__MODULE__{status: s}), do: s in @terminal
  end

  @doc "Initiate a refund for a completed payment."
  @spec initiate(Client.t(), map()) :: {:ok, Refund.t()} | {:error, Error.t()}
  def initiate(%Client{http: http}, params) do
    initiation =
      %{}
      |> put_if("transferId", params[:transfer_id])
      |> put_if("refId", params[:ref_id])
      |> put_if("amount", Types.encode_amount(params[:amount]))
      |> put_if("remittanceInformationPrimary", params[:remittance_information_primary])
      |> put_if("debtor", Types.PartyAccount.to_map(params[:debtor]))
      |> put_if("creditor", Types.PartyAccount.to_map(params[:creditor]))

    with {:ok, resp} <- HTTP.post(http, "/refunds", %{"refundInitiation" => initiation}) do
      {:ok, Refund.from_map(resp["refund"])}
    end
  end

  @doc "Retrieve a refund by ID."
  @spec get(Client.t(), String.t()) :: {:ok, Refund.t()} | {:error, Error.t()}
  def get(%Client{http: http}, refund_id) do
    with {:ok, resp} <- HTTP.get(http, "/refunds/" <> refund_id) do
      {:ok, Refund.from_map(resp["refund"])}
    end
  end

  @doc "List refunds. Requires `:limit` option."
  @spec list(Client.t(), keyword()) ::
          {:ok, %{refunds: [Refund.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]},
      {"transferId", opts[:transfer_id]},
      {"createdAfter", opts[:created_after]},
      {"createdBefore", opts[:created_before]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/refunds", query: query) do
      {:ok,
       %{
         refunds: Enum.map(resp["refunds"] || [], &Refund.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.Payouts do
  @moduledoc "Token.io Payouts API — send money from settlement accounts."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Payout do
    @moduledoc "A payout resource."

    @terminal ~w[INITIATION_COMPLETED INITIATION_REJECTED INITIATION_FAILED]

    @type t :: %__MODULE__{
            id: String.t(),
            status: String.t(),
            error_info: Types.ErrorInfo.t() | nil,
            created_at: DateTime.t() | nil,
            updated_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [:id, :status, :error_info, :created_at, :updated_at, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        status: m["status"] || "",
        error_info: Types.ErrorInfo.from_map(m["errorInfo"]),
        created_at: Types.parse_datetime(m["createdDateTime"]),
        updated_at: Types.parse_datetime(m["updatedDateTime"]),
        raw: m
      }
    end

    @spec final?(t()) :: boolean()
    def final?(%__MODULE__{status: s}), do: s in @terminal
  end

  @doc "Initiate a payout."
  @spec initiate(Client.t(), map()) :: {:ok, Payout.t()} | {:error, Error.t()}
  def initiate(%Client{http: http}, params) do
    initiation =
      %{}
      |> put_if("refId", params[:ref_id])
      |> put_if("amount", Types.encode_amount(params[:amount]))
      |> put_if("creditor", Types.PartyAccount.to_map(params[:creditor]))
      |> put_if("debtor", Types.PartyAccount.to_map(params[:debtor]))
      |> put_if("remittanceInformationPrimary", params[:remittance_information_primary])
      |> put_if("executionDate", params[:execution_date])
      |> put_if("localInstrument", params[:local_instrument])

    with {:ok, resp} <- HTTP.post(http, "/payouts", %{"payoutInitiation" => initiation}) do
      {:ok, Payout.from_map(resp["payout"])}
    end
  end

  @doc "Retrieve a payout by ID."
  @spec get(Client.t(), String.t()) :: {:ok, Payout.t()} | {:error, Error.t()}
  def get(%Client{http: http}, payout_id) do
    with {:ok, resp} <- HTTP.get(http, "/payouts/" <> payout_id) do
      {:ok, Payout.from_map(resp["payout"])}
    end
  end

  @doc "List payouts. Requires `:limit` option."
  @spec list(Client.t(), keyword()) ::
          {:ok, %{payouts: [Payout.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]},
      {"createdAfter", opts[:created_after]},
      {"createdBefore", opts[:created_before]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/payouts", query: query) do
      {:ok,
       %{
         payouts: Enum.map(resp["payouts"] || [], &Payout.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.Settlement do
  @moduledoc "Token.io Settlement Accounts API — virtual accounts, rules, and transactions."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Account do
    @moduledoc "A virtual settlement account."

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t() | nil,
            currency: String.t() | nil,
            iban: String.t() | nil,
            account_number: String.t() | nil,
            sort_code: String.t() | nil,
            balance: String.t() | nil,
            created_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [
      :id,
      :name,
      :currency,
      :iban,
      :account_number,
      :sort_code,
      :balance,
      :created_at,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        name: m["name"],
        currency: m["currency"],
        iban: m["iban"],
        account_number: m["accountNumber"],
        sort_code: m["sortCode"],
        balance: m["balance"],
        created_at: Types.parse_datetime(m["createdDateTime"]),
        raw: m
      }
    end
  end

  defmodule Rule do
    @moduledoc "A settlement rule for automatic fund management."

    @type t :: %__MODULE__{
            id: String.t(),
            account_id: String.t() | nil,
            rule_type: String.t() | nil,
            threshold_amount: String.t() | nil,
            currency: String.t() | nil,
            enabled: boolean(),
            raw: map()
          }

    defstruct [
      :id,
      :account_id,
      :rule_type,
      :threshold_amount,
      :currency,
      enabled: false,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        account_id: m["accountId"],
        rule_type: m["ruleType"],
        threshold_amount: m["thresholdAmount"],
        currency: m["currency"],
        enabled: m["enabled"] == true,
        raw: m
      }
    end
  end

  defmodule Transaction do
    @moduledoc "A settlement account transaction."

    @type t :: %__MODULE__{
            id: String.t(),
            account_id: String.t() | nil,
            amount: Types.Amount.t() | nil,
            type: String.t() | nil,
            status: String.t() | nil,
            reference: String.t() | nil,
            created_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [:id, :account_id, :amount, :type, :status, :reference, :created_at, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        account_id: m["accountId"],
        amount: Types.Amount.from_map(m["amount"]),
        type: m["type"],
        status: m["status"],
        reference: m["reference"],
        created_at: Types.parse_datetime(m["createdDateTime"]),
        raw: m
      }
    end
  end

  @doc "Create a virtual settlement account."
  @spec create_account(Client.t(), String.t(), keyword()) ::
          {:ok, Account.t()} | {:error, Error.t()}
  def create_account(%Client{http: http}, currency, opts \\ []) do
    body = put_if(%{"currency" => currency}, "name", opts[:name])

    with {:ok, resp} <- HTTP.post(http, "/virtual-accounts", body) do
      {:ok, Account.from_map(resp["virtualAccount"])}
    end
  end

  @doc "List settlement accounts."
  @spec list_accounts(Client.t(), keyword()) ::
          {:ok, %{accounts: [Account.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_accounts(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.get(opts, :limit, 50))},
      {"offset", opts[:offset]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/virtual-accounts", query: query) do
      {:ok,
       %{
         accounts: Enum.map(resp["virtualAccounts"] || [], &Account.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve a settlement account by ID."
  @spec get_account(Client.t(), String.t()) :: {:ok, Account.t()} | {:error, Error.t()}
  def get_account(%Client{http: http}, account_id) do
    with {:ok, resp} <- HTTP.get(http, "/virtual-accounts/" <> account_id) do
      {:ok, Account.from_map(resp["virtualAccount"])}
    end
  end

  @doc "List transactions for a settlement account."
  @spec list_transactions(Client.t(), String.t(), keyword()) ::
          {:ok, %{transactions: [Transaction.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_transactions(%Client{http: http}, account_id, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.get(opts, :limit, 50))},
      {"offset", opts[:offset]}
    ]

    path = "/virtual-accounts/" <> account_id <> "/transactions"

    with {:ok, resp} <- HTTP.get(http, path, query: query) do
      {:ok,
       %{
         transactions: Enum.map(resp["transactions"] || [], &Transaction.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve a single settlement transaction."
  @spec get_transaction(Client.t(), String.t(), String.t()) ::
          {:ok, Transaction.t()} | {:error, Error.t()}
  def get_transaction(%Client{http: http}, account_id, tx_id) do
    path = "/virtual-accounts/" <> account_id <> "/transactions/" <> tx_id

    with {:ok, resp} <- HTTP.get(http, path) do
      {:ok, Transaction.from_map(resp["transaction"])}
    end
  end

  @doc "Create a settlement rule for an account."
  @spec create_rule(Client.t(), String.t(), map()) :: {:ok, Rule.t()} | {:error, Error.t()}
  def create_rule(%Client{http: http}, account_id, params) do
    body =
      %{}
      |> put_if("ruleType", params[:rule_type])
      |> put_if("thresholdAmount", params[:threshold_amount])
      |> put_if("currency", params[:currency])

    path = "/virtual-accounts/" <> account_id <> "/settlement-rules"

    with {:ok, resp} <- HTTP.post(http, path, body) do
      {:ok, Rule.from_map(resp["settlementRule"])}
    end
  end

  @doc "List settlement rules for an account."
  @spec list_rules(Client.t(), String.t(), keyword()) ::
          {:ok, %{rules: [Rule.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list_rules(%Client{http: http}, account_id, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.get(opts, :limit, 50))},
      {"offset", opts[:offset]}
    ]

    path = "/virtual-accounts/" <> account_id <> "/settlement-rules"

    with {:ok, resp} <- HTTP.get(http, path, query: query) do
      {:ok,
       %{
         rules: Enum.map(resp["settlementRules"] || [], &Rule.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Delete a settlement rule."
  @spec delete_rule(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_rule(%Client{http: http}, account_id, rule_id) do
    path = "/virtual-accounts/" <> account_id <> "/settlement-rules/" <> rule_id

    with {:ok, _} <- HTTP.delete(http, path) do
      :ok
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.Transfers do
  @moduledoc "Token.io Transfers API — Payments v1 token redemption."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Transfer do
    @moduledoc "A transfer resource (Payments v1)."

    @terminal ~w[SUCCESS FAILED CANCELED]

    @type t :: %__MODULE__{
            id: String.t(),
            token_id: String.t() | nil,
            status: String.t(),
            refund_details: Types.RefundDetails.t() | nil,
            created_at: DateTime.t() | nil,
            updated_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [:id, :token_id, :status, :refund_details, :created_at, :updated_at, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        token_id: m["tokenId"],
        status: m["status"] || "",
        refund_details: Types.RefundDetails.from_map(m["refundDetails"]),
        created_at: Types.parse_datetime(m["createdDateTime"]),
        updated_at: Types.parse_datetime(m["updatedDateTime"]),
        raw: m
      }
    end

    @spec final?(t()) :: boolean()
    def final?(%__MODULE__{status: s}), do: s in @terminal
  end

  @doc "Redeem a payment token."
  @spec redeem(Client.t(), String.t(), keyword()) :: {:ok, Transfer.t()} | {:error, Error.t()}
  def redeem(%Client{http: http}, token_id, opts \\ []) do
    body =
      %{"tokenId" => token_id}
      |> put_if("refId", opts[:ref_id])
      |> put_if("amount", Types.encode_amount(opts[:amount]))

    with {:ok, resp} <- HTTP.post(http, "/transfers", body) do
      {:ok, Transfer.from_map(resp["transfer"])}
    end
  end

  @doc "Retrieve a transfer by ID."
  @spec get(Client.t(), String.t()) :: {:ok, Transfer.t()} | {:error, Error.t()}
  def get(%Client{http: http}, transfer_id) do
    with {:ok, resp} <- HTTP.get(http, "/transfers/" <> transfer_id) do
      {:ok, Transfer.from_map(resp["transfer"])}
    end
  end

  @doc "List transfers. Requires `:limit` option."
  @spec list(Client.t(), keyword()) ::
          {:ok, %{transfers: [Transfer.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.fetch!(opts, :limit))},
      {"offset", opts[:offset]},
      {"tokenId", opts[:token_id]},
      {"createdAfter", opts[:created_after]},
      {"createdBefore", opts[:created_before]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/transfers", query: query) do
      {:ok,
       %{
         transfers: Enum.map(resp["transfers"] || [], &Transfer.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.Tokens do
  @moduledoc "Token.io Tokens API — list, retrieve, and cancel authorisation tokens."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Token do
    @moduledoc "An authorisation token."

    @type t :: %__MODULE__{
            id: String.t(),
            type: String.t() | nil,
            status: String.t() | nil,
            created_at: DateTime.t() | nil,
            expires_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [:id, :type, :status, :created_at, :expires_at, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        type: m["type"],
        status: m["status"],
        created_at: Types.parse_datetime(m["createdDateTime"]),
        expires_at: Types.parse_datetime(m["expiresDateTime"]),
        raw: m
      }
    end
  end

  @doc "List tokens."
  @spec list(Client.t(), keyword()) ::
          {:ok, %{tokens: [Token.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.get(opts, :limit, 50))},
      {"offset", opts[:offset]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/tokens", query: query) do
      {:ok,
       %{
         tokens: Enum.map(resp["tokens"] || [], &Token.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve a token by ID."
  @spec get(Client.t(), String.t()) :: {:ok, Token.t()} | {:error, Error.t()}
  def get(%Client{http: http}, token_id) do
    with {:ok, resp} <- HTTP.get(http, "/tokens/" <> token_id) do
      {:ok, Token.from_map(resp["token"])}
    end
  end

  @doc "Cancel a token."
  @spec cancel(Client.t(), String.t()) :: {:ok, Token.t()} | {:error, Error.t()}
  def cancel(%Client{http: http}, token_id) do
    with {:ok, resp} <- HTTP.put(http, "/tokens/" <> token_id <> "/cancel", %{}) do
      {:ok, Token.from_map(resp["token"])}
    end
  end
end

# =============================================================================

defmodule Tokenio.TokenRequests do
  @moduledoc "Token.io Token Requests API — Payments v1 / AIS legacy flow."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP

  defmodule TokenRequest do
    @moduledoc "A stored token request."

    @type t :: %__MODULE__{
            token_request_id: String.t(),
            status: String.t() | nil,
            redirect_url: String.t() | nil,
            token_id: String.t() | nil,
            raw: map()
          }

    defstruct [:token_request_id, :status, :redirect_url, :token_id, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        token_request_id: m["tokenRequestId"],
        status: m["status"],
        redirect_url: m["redirectUrl"],
        token_id: m["tokenId"],
        raw: m
      }
    end
  end

  @doc "Store a new token request."
  @spec store(Client.t(), map()) :: {:ok, TokenRequest.t()} | {:error, Error.t()}
  def store(%Client{http: http}, params) do
    body =
      %{"requestPayload" => params[:request_payload]}
      |> put_if("options", params[:options])
      |> put_if("redirectUrl", params[:redirect_url])

    with {:ok, resp} <- HTTP.post(http, "/token-requests", body) do
      {:ok, TokenRequest.from_map(resp["tokenRequest"])}
    end
  end

  @doc "Retrieve a token request by ID."
  @spec get(Client.t(), String.t()) :: {:ok, TokenRequest.t()} | {:error, Error.t()}
  def get(%Client{http: http}, request_id) do
    with {:ok, resp} <- HTTP.get(http, "/token-requests/" <> request_id) do
      {:ok, TokenRequest.from_map(resp["tokenRequest"])}
    end
  end

  @doc "Get the result of a completed token request."
  @spec get_result(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_result(%Client{http: http}, request_id) do
    with {:ok, resp} <- HTTP.get(http, "/token-requests/" <> request_id <> "/result") do
      {:ok, resp["tokenRequestResult"] || resp}
    end
  end

  @doc "Initiate bank authorization for a token request."
  @spec initiate_bank_auth(Client.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def initiate_bank_auth(%Client{http: http}, request_id, bank_id) do
    HTTP.post(http, "/token-requests/" <> request_id <> "/authorize", %{"bankId" => bank_id})
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.AccountOnFile do
  @moduledoc "Token.io Account on File API — tokenized account storage."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule TokenizedAccount do
    @moduledoc "A tokenized (stored) bank account reference."

    @type t :: %__MODULE__{
            id: String.t(),
            bank_id: String.t() | nil,
            status: String.t() | nil,
            display_name: String.t() | nil,
            currency: String.t() | nil,
            created_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [:id, :bank_id, :status, :display_name, :currency, :created_at, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        bank_id: m["bankId"],
        status: m["status"],
        display_name: m["displayName"],
        currency: m["currency"],
        created_at: Types.parse_datetime(m["createdDateTime"]),
        raw: m
      }
    end
  end

  @doc "Create a new tokenized account."
  @spec create(Client.t(), String.t(), keyword()) ::
          {:ok, TokenizedAccount.t()} | {:error, Error.t()}
  def create(%Client{http: http}, bank_id, opts \\ []) do
    body =
      %{"bankId" => bank_id}
      |> put_if("callbackUrl", opts[:callback_url])
      |> put_if("callbackState", opts[:callback_state])

    with {:ok, resp} <- HTTP.post(http, "/tokenized-accounts", body) do
      {:ok, TokenizedAccount.from_map(resp["tokenizedAccount"])}
    end
  end

  @doc "Retrieve a tokenized account by ID."
  @spec get(Client.t(), String.t()) :: {:ok, TokenizedAccount.t()} | {:error, Error.t()}
  def get(%Client{http: http}, id) do
    with {:ok, resp} <- HTTP.get(http, "/tokenized-accounts/" <> id) do
      {:ok, TokenizedAccount.from_map(resp["tokenizedAccount"])}
    end
  end

  @doc "Delete a tokenized account."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{http: http}, id) do
    with {:ok, _} <- HTTP.delete(http, "/tokenized-accounts/" <> id) do
      :ok
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.SubTPPs do
  @moduledoc "Token.io Sub-TPPs API — manage unregulated TPPs under a regulated parent."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule SubTPP do
    @moduledoc "A sub-TPP entity."

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t() | nil,
            status: String.t() | nil,
            created_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [:id, :name, :status, :created_at, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        name: m["name"],
        status: m["status"],
        created_at: Types.parse_datetime(m["createdDateTime"]),
        raw: m
      }
    end
  end

  @doc "Create a sub-TPP."
  @spec create(Client.t(), String.t(), keyword()) :: {:ok, SubTPP.t()} | {:error, Error.t()}
  def create(%Client{http: http}, name, opts \\ []) do
    body = put_if(%{"name" => name}, "displayName", opts[:display_name])

    with {:ok, resp} <- HTTP.post(http, "/sub-tpps", body) do
      {:ok, SubTPP.from_map(resp["subTpp"])}
    end
  end

  @doc "List sub-TPPs."
  @spec list(Client.t(), keyword()) ::
          {:ok, %{sub_tpps: [SubTPP.t()], page_info: Types.PageInfo.t() | nil}}
          | {:error, Error.t()}
  def list(%Client{http: http}, opts \\ []) do
    query = [
      {"limit", Integer.to_string(Keyword.get(opts, :limit, 50))},
      {"offset", opts[:offset]}
    ]

    with {:ok, resp} <- HTTP.get(http, "/sub-tpps", query: query) do
      {:ok,
       %{
         sub_tpps: Enum.map(resp["subTpps"] || [], &SubTPP.from_map/1),
         page_info: Types.PageInfo.from_map(resp["pageInfo"])
       }}
    end
  end

  @doc "Retrieve a sub-TPP by ID."
  @spec get(Client.t(), String.t()) :: {:ok, SubTPP.t()} | {:error, Error.t()}
  def get(%Client{http: http}, id) do
    with {:ok, resp} <- HTTP.get(http, "/sub-tpps/" <> id) do
      {:ok, SubTPP.from_map(resp["subTpp"])}
    end
  end

  @doc "Delete a sub-TPP."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{http: http}, id) do
    with {:ok, _} <- HTTP.delete(http, "/sub-tpps/" <> id) do
      :ok
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.AuthKeys do
  @moduledoc "Token.io Authentication Keys API — manage RSA/EC signing keys."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule MemberKey do
    @moduledoc "A registered public authentication key."

    @type t :: %__MODULE__{
            id: String.t(),
            algorithm: String.t() | nil,
            level: String.t() | nil,
            status: String.t() | nil,
            created_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [:id, :algorithm, :level, :status, :created_at, raw: %{}]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        id: m["id"],
        algorithm: m["algorithm"],
        level: m["level"],
        status: m["status"],
        created_at: Types.parse_datetime(m["createdDateTime"]),
        raw: m
      }
    end
  end

  @doc "Submit a new public key."
  @spec submit(Client.t(), String.t(), keyword()) ::
          {:ok, MemberKey.t()} | {:error, Error.t()}
  def submit(%Client{http: http}, public_key, opts \\ []) do
    body =
      %{"publicKey" => public_key}
      |> put_if("algorithm", opts[:algorithm])
      |> put_if("level", opts[:level])

    with {:ok, resp} <- HTTP.post(http, "/member-keys", body) do
      {:ok, MemberKey.from_map(resp["memberKey"])}
    end
  end

  @doc "List all registered keys."
  @spec list(Client.t()) :: {:ok, [MemberKey.t()]} | {:error, Error.t()}
  def list(%Client{http: http}) do
    with {:ok, resp} <- HTTP.get(http, "/member-keys") do
      {:ok, Enum.map(resp["memberKeys"] || [], &MemberKey.from_map/1)}
    end
  end

  @doc "Retrieve a key by ID."
  @spec get(Client.t(), String.t()) :: {:ok, MemberKey.t()} | {:error, Error.t()}
  def get(%Client{http: http}, key_id) do
    with {:ok, resp} <- HTTP.get(http, "/member-keys/" <> key_id) do
      {:ok, MemberKey.from_map(resp["memberKey"])}
    end
  end

  @doc "Delete a key by ID."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{http: http}, key_id) do
    with {:ok, _} <- HTTP.delete(http, "/member-keys/" <> key_id) do
      :ok
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end

# =============================================================================

defmodule Tokenio.Reports do
  @moduledoc "Token.io Reports API — bank operational status."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP

  defmodule BankStatus do
    @moduledoc "Operational status for a single bank connection."

    @type t :: %__MODULE__{
            bank_id: String.t(),
            status: String.t() | nil,
            status_message: String.t() | nil,
            ais_available: boolean(),
            pis_available: boolean(),
            vrp_available: boolean(),
            raw: map()
          }

    defstruct [
      :bank_id,
      :status,
      :status_message,
      ais_available: false,
      pis_available: false,
      vrp_available: false,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      %__MODULE__{
        bank_id: m["bankId"] || "",
        status: m["status"],
        status_message: m["statusMessage"],
        ais_available: m["aisAvailable"] == true,
        pis_available: m["pisAvailable"] == true,
        vrp_available: m["vrpAvailable"] == true,
        raw: m
      }
    end
  end

  @doc "List operational statuses for all banks."
  @spec list_bank_statuses(Client.t()) :: {:ok, [BankStatus.t()]} | {:error, Error.t()}
  def list_bank_statuses(%Client{http: http}) do
    with {:ok, resp} <- HTTP.get(http, "/bank-statuses") do
      {:ok, Enum.map(resp["bankStatuses"] || [], &BankStatus.from_map/1)}
    end
  end

  @doc "Retrieve the status for a specific bank."
  @spec get_bank_status(Client.t(), String.t()) :: {:ok, BankStatus.t()} | {:error, Error.t()}
  def get_bank_status(%Client{http: http}, bank_id) do
    with {:ok, resp} <- HTTP.get(http, "/bank-statuses/" <> bank_id) do
      {:ok, BankStatus.from_map(resp["bankStatus"])}
    end
  end
end

# =============================================================================

defmodule Tokenio.Verification do
  @moduledoc "Token.io Verification API — account ownership verification."

  alias Tokenio.Client
  alias Tokenio.Error
  alias Tokenio.HTTP.Client, as: HTTP
  alias Tokenio.Types

  defmodule Check do
    @moduledoc "An account verification check result."

    @type t :: %__MODULE__{
            id: String.t(),
            status: String.t(),
            account_verified: boolean() | nil,
            name_matched: boolean() | nil,
            redirect_url: String.t() | nil,
            error_info: Types.ErrorInfo.t() | nil,
            created_at: DateTime.t() | nil,
            raw: map()
          }

    defstruct [
      :id,
      :status,
      :account_verified,
      :name_matched,
      :redirect_url,
      :error_info,
      :created_at,
      raw: %{}
    ]

    @spec from_map(map() | nil) :: t() | nil
    def from_map(nil), do: nil

    def from_map(m) do
      auth = m["authentication"] || %{}

      %__MODULE__{
        id: m["id"],
        status: m["status"] || "",
        account_verified: m["accountVerified"],
        name_matched: m["nameMatched"],
        redirect_url: auth["redirectUrl"],
        error_info: Types.ErrorInfo.from_map(m["errorInfo"]),
        created_at: Types.parse_datetime(m["createdDateTime"]),
        raw: m
      }
    end

    @doc "Returns `true` when the verification check is in a terminal state."
    @spec final?(t()) :: boolean()
    def final?(%__MODULE__{status: s}), do: s in ~w[COMPLETED FAILED]
  end

  @doc """
  Initiate an account ownership verification check.

  ### Required fields
  - `:bank_id`
  - `:account` — map with at least one of `:account_number`/`:sort_code` or `:iban`
  """
  @spec initiate(Client.t(), map()) :: {:ok, Check.t()} | {:error, Error.t()}
  def initiate(%Client{http: http}, params) do
    account_params = params[:account] || %{}

    account =
      %{}
      |> put_if(
        "accountNumber",
        account_params[:account_number] || account_params["accountNumber"]
      )
      |> put_if("sortCode", account_params[:sort_code] || account_params["sortCode"])
      |> put_if("iban", account_params[:iban] || account_params["iban"])
      |> put_if("name", account_params[:name] || account_params["name"])

    body =
      %{"bankId" => params[:bank_id], "account" => account}
      |> put_if("callbackUrl", params[:callback_url])
      |> put_if("callbackState", params[:callback_state])

    with {:ok, resp} <- HTTP.post(http, "/verification", body) do
      {:ok, Check.from_map(resp["verification"])}
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)
end
