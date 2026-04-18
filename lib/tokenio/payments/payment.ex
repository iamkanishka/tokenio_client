defmodule TokenioClient.Payments.Payment do
  @moduledoc """
  A Token.io payment resource returned by the Payments v2 API.

  ## Status predicates

      payment = TokenioClient.Payments.Payment.from_map(raw)

      TokenioClient.Payments.Payment.final?(payment)
      TokenioClient.Payments.Payment.requires_redirect?(payment)
      TokenioClient.Payments.Payment.requires_embedded_auth?(payment)
      TokenioClient.Payments.Payment.completed?(payment)
      TokenioClient.Payments.Payment.failed?(payment)
  """

  alias TokenioClient.Types

  @terminal_statuses ~w[
    INITIATION_COMPLETED
    INITIATION_REJECTED
    INITIATION_REJECTED_INSUFFICIENT_FUNDS
    INITIATION_FAILED
    INITIATION_DECLINED
    INITIATION_EXPIRED
    INITIATION_NO_FINAL_STATUS_AVAILABLE
    SETTLEMENT_COMPLETED
    SETTLEMENT_INCOMPLETE
    CANCELED
  ]

  @redirect_statuses ~w[
    INITIATION_PENDING_REDIRECT_AUTH
    INITIATION_PENDING_REDIRECT_AUTH_VERIFICATION
    INITIATION_PENDING_REDIRECT_HP
    INITIATION_PENDING_REDIRECT_PBL
  ]

  @embedded_statuses ~w[
    INITIATION_PENDING_EMBEDDED_AUTH
    INITIATION_PENDING_EMBEDDED_AUTH_VERIFICATION
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          member_id: String.t() | nil,
          status: String.t(),
          status_reason_information: String.t() | nil,
          bank_payment_id: String.t() | nil,
          bank_transaction_id: String.t() | nil,
          redirect_url: String.t() | nil,
          embedded_auth_fields: [Types.EmbeddedField.t()],
          refund_details: Types.RefundDetails.t() | nil,
          error_info: Types.ErrorInfo.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          raw: map()
        }

  defstruct [
    :id,
    :member_id,
    :status,
    :status_reason_information,
    :bank_payment_id,
    :bank_transaction_id,
    :redirect_url,
    :refund_details,
    :error_info,
    :created_at,
    :updated_at,
    embedded_auth_fields: [],
    raw: %{}
  ]

  @doc "Build a `Payment` from a raw API response map."
  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(m) when is_map(m) do
    auth = m["authentication"] || %{}

    %__MODULE__{
      id: m["id"],
      member_id: m["memberId"],
      status: m["status"] || "",
      status_reason_information: m["statusReasonInformation"],
      bank_payment_id: m["bankPaymentId"],
      bank_transaction_id: m["bankTransactionId"],
      redirect_url: auth["redirectUrl"],
      embedded_auth_fields: Enum.map(auth["embeddedAuth"] || [], &Types.EmbeddedField.from_map/1),
      refund_details: Types.RefundDetails.from_map(m["refundDetails"]),
      error_info: Types.ErrorInfo.from_map(m["errorInfo"]),
      created_at: Types.parse_datetime(m["createdDateTime"]),
      updated_at: Types.parse_datetime(m["updatedDateTime"]),
      raw: m
    }
  end

  @doc "Returns `true` when the payment has reached a terminal state."
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{status: s}), do: s in @terminal_statuses

  @doc "Returns `true` when the PSU must be redirected to complete authentication."
  @spec requires_redirect?(t()) :: boolean()
  def requires_redirect?(%__MODULE__{status: s}), do: s in @redirect_statuses

  @doc "Returns `true` when embedded auth fields must be collected and submitted."
  @spec requires_embedded_auth?(t()) :: boolean()
  def requires_embedded_auth?(%__MODULE__{status: s}), do: s in @embedded_statuses

  @doc "Returns `true` when the bank is performing decoupled (push-notification) authentication."
  @spec decoupled_auth?(t()) :: boolean()
  def decoupled_auth?(%__MODULE__{status: "INITIATION_PENDING_DECOUPLED_AUTH"}), do: true
  def decoupled_auth?(%__MODULE__{}), do: false

  @doc "Returns `true` when the payment completed successfully."
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{status: "INITIATION_COMPLETED"}), do: true
  def completed?(%__MODULE__{status: "SETTLEMENT_COMPLETED"}), do: true
  def completed?(%__MODULE__{}), do: false

  @doc "Returns `true` when the payment failed for any reason."
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{status: s})
      when s in ~w[
        INITIATION_FAILED
        INITIATION_REJECTED
        INITIATION_REJECTED_INSUFFICIENT_FUNDS
        INITIATION_DECLINED
        INITIATION_EXPIRED
      ],
      do: true

  def failed?(%__MODULE__{}), do: false
end
