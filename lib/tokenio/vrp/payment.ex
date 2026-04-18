defmodule Tokenio.VRP.Payment do
  @moduledoc """
  A single VRP payment resource returned by the Token.io VRP API.

  Individual payments are made against an authorised `Tokenio.VRP.Consent`.

  ## Status predicates

      Tokenio.VRP.Payment.final?(payment)
      Tokenio.VRP.Payment.completed?(payment)
  """

  alias Tokenio.Types

  @terminal ~w[
    INITIATION_COMPLETED
    INITIATION_REJECTED
    INITIATION_REJECTED_INSUFFICIENT_FUNDS
    INITIATION_FAILED
    INITIATION_NO_FINAL_STATUS_AVAILABLE
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          member_id: String.t() | nil,
          status: String.t(),
          bank_vrp_id: String.t() | nil,
          status_reason_information: String.t() | nil,
          refund_details: Types.RefundDetails.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          raw: map()
        }

  defstruct [
    :id,
    :member_id,
    :status,
    :bank_vrp_id,
    :status_reason_information,
    :refund_details,
    :created_at,
    :updated_at,
    raw: %{}
  ]

  @doc "Build a `Payment` from a raw API response map."
  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(m) when is_map(m) do
    %__MODULE__{
      id: m["id"],
      member_id: m["memberId"],
      status: m["status"] || "",
      bank_vrp_id: m["bankVrpId"],
      status_reason_information: m["statusReasonInformation"],
      refund_details: Types.RefundDetails.from_map(m["refundDetails"]),
      created_at: Types.parse_datetime(m["createdDateTime"]),
      updated_at: Types.parse_datetime(m["updatedDateTime"]),
      raw: m
    }
  end

  @doc "Returns `true` when the VRP payment is in a terminal state."
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{status: s}), do: s in @terminal

  @doc "Returns `true` when the VRP payment completed successfully."
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{status: "INITIATION_COMPLETED"}), do: true
  def completed?(%__MODULE__{}), do: false
end
