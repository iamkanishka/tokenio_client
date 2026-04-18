defmodule TokenioClient.VRP.Consent do
  @moduledoc """
  A Token.io VRP consent resource.

  A consent represents the PSU's authorisation for a TPP to make variable
  recurring payments from their account up to the agreed limits.

  ## Status predicates

      TokenioClient.VRP.Consent.final?(consent)
      TokenioClient.VRP.Consent.authorized?(consent)
      TokenioClient.VRP.Consent.requires_redirect?(consent)
  """

  alias TokenioClient.Types

  @terminal ~w[AUTHORIZED REJECTED REVOKED FAILED]
  @redirect ~w[PENDING_REDIRECT_AUTH PENDING_REDIRECT_AUTH_VERIFICATION]

  @type t :: %__MODULE__{
          id: String.t(),
          member_id: String.t() | nil,
          status: String.t(),
          bank_vrp_consent_id: String.t() | nil,
          redirect_url: String.t() | nil,
          embedded_auth_fields: [Types.EmbeddedField.t()],
          status_reason_information: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          raw: map()
        }

  defstruct [
    :id,
    :member_id,
    :status,
    :bank_vrp_consent_id,
    :redirect_url,
    :status_reason_information,
    :created_at,
    :updated_at,
    embedded_auth_fields: [],
    raw: %{}
  ]

  @doc "Build a `Consent` from a raw API response map."
  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil

  def from_map(m) when is_map(m) do
    auth = m["authentication"] || %{}

    %__MODULE__{
      id: m["id"],
      member_id: m["memberId"],
      status: m["status"] || "",
      bank_vrp_consent_id: m["bankVrpConsentId"],
      redirect_url: auth["redirectUrl"],
      embedded_auth_fields: Enum.map(auth["embeddedAuth"] || [], &Types.EmbeddedField.from_map/1),
      status_reason_information: m["statusReasonInformation"],
      created_at: Types.parse_datetime(m["createdDateTime"]),
      updated_at: Types.parse_datetime(m["updatedDateTime"]),
      raw: m
    }
  end

  @doc "Returns `true` when the consent is in a terminal state."
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{status: s}), do: s in @terminal

  @doc "Returns `true` when the PSU must be redirected to authorise."
  @spec requires_redirect?(t()) :: boolean()
  def requires_redirect?(%__MODULE__{status: s}), do: s in @redirect

  @doc "Returns `true` when the consent is fully authorised."
  @spec authorized?(t()) :: boolean()
  def authorized?(%__MODULE__{status: "AUTHORIZED"}), do: true
  def authorized?(%__MODULE__{}), do: false
end
