defmodule TokenioClient.Error do
  @moduledoc """
  Typed error returned by all Token.io API functions.

  ## Error codes

  | Code | HTTP status |
  |---|---|
  | `:unauthorized` | 401 |
  | `:forbidden` | 403 |
  | `:not_found` | 404 |
  | `:conflict` | 409 |
  | `:validation_error` | 400 / 422 |
  | `:rate_limit_exceeded` | 429 |
  | `:internal_server_error` | 500 |
  | `:bad_gateway` | 502 |
  | `:service_unavailable` | 503 |
  | `:timeout` | 504 |
  | `:unknown` | other |

  ## Pattern matching

      case TokenioClient.Payments.get(client, id) do
        {:ok, payment} -> payment
        {:error, %TokenioClient.Error{code: :not_found}} -> nil
        {:error, %TokenioClient.Error{code: :rate_limit_exceeded, retry_after: ra}} ->
          Process.sleep((ra || 5) * 1_000)
        {:error, err} -> raise err
      end
  """

  @type code ::
          :unauthorized
          | :forbidden
          | :not_found
          | :conflict
          | :validation_error
          | :rate_limit_exceeded
          | :internal_server_error
          | :bad_gateway
          | :service_unavailable
          | :timeout
          | :unknown

  @type t :: %__MODULE__{
          code: code(),
          message: String.t(),
          status: non_neg_integer(),
          request_id: String.t() | nil,
          details: map() | nil,
          retry_after: non_neg_integer() | nil
        }

  defexception [:code, :message, :status, :request_id, :details, :retry_after]

  @spec message(t()) :: String.t()
  @impl Exception
  def message(%__MODULE__{code: code, message: msg, status: status, request_id: rid}) do
    base = "[#{code}] #{msg} (HTTP #{status})"
    if rid, do: "#{base} trace_id=#{rid}", else: base
  end

  @doc "Returns `true` if the error is retryable (429, 500, 502, 503, 504)."
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{status: s}) when s in [429, 500, 502, 503, 504], do: true
  def retryable?(%__MODULE__{}), do: false

  @doc "Returns `true` if the error is a 404 Not Found."
  @spec not_found?(t()) :: boolean()
  def not_found?(%__MODULE__{code: :not_found}), do: true
  def not_found?(%__MODULE__{}), do: false

  @doc "Returns `true` if the error is a 401 Unauthorized."
  @spec unauthorized?(t()) :: boolean()
  def unauthorized?(%__MODULE__{code: :unauthorized}), do: true
  def unauthorized?(%__MODULE__{}), do: false

  @doc "Returns `true` if the error is a 429 Rate Limit Exceeded."
  @spec rate_limited?(t()) :: boolean()
  def rate_limited?(%__MODULE__{code: :rate_limit_exceeded}), do: true
  def rate_limited?(%__MODULE__{}), do: false

  # ---------------------------------------------------------------------------
  # Internal constructors (not part of public API)
  # ---------------------------------------------------------------------------

  @doc false
  @spec from_response(non_neg_integer(), map(), String.t() | nil, String.t() | nil) :: t()
  def from_response(status, body, request_id, retry_after_header) do
    raw_code = Map.get(body, "code", "")
    msg = Map.get(body, "message") || default_message(status)
    details = Map.get(body, "details")

    retry_after =
      case Integer.parse(retry_after_header || "") do
        {n, ""} -> n
        _ -> nil
      end

    %__MODULE__{
      code: resolve_code(status, raw_code),
      message: msg,
      status: status,
      request_id: request_id,
      details: details,
      retry_after: retry_after
    }
  end

  @doc false
  @spec network_error(term()) :: t()
  def network_error(reason) do
    %__MODULE__{
      code: :unknown,
      message: "Network error: #{inspect(reason)}",
      status: 0,
      request_id: nil,
      details: nil,
      retry_after: nil
    }
  end

  @doc false
  @spec validation(String.t()) :: t()
  def validation(msg) do
    %__MODULE__{code: :unknown, message: msg, status: 0}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @code_map %{
    "UNAUTHORIZED" => :unauthorized,
    "FORBIDDEN" => :forbidden,
    "NOT_FOUND" => :not_found,
    "CONFLICT" => :conflict,
    "VALIDATION_ERROR" => :validation_error,
    "RATE_LIMIT_EXCEEDED" => :rate_limit_exceeded,
    "INTERNAL_SERVER_ERROR" => :internal_server_error,
    "SERVICE_UNAVAILABLE" => :service_unavailable,
    "TIMEOUT" => :timeout,
    "BAD_GATEWAY" => :bad_gateway,
    "DEADLINE_EXCEEDED" => :timeout
  }

  @status_map %{
    401 => :unauthorized,
    403 => :forbidden,
    404 => :not_found,
    409 => :conflict,
    400 => :validation_error,
    422 => :validation_error,
    429 => :rate_limit_exceeded,
    500 => :internal_server_error,
    502 => :bad_gateway,
    503 => :service_unavailable,
    504 => :timeout
  }

  defp resolve_code(_status, raw) when raw != "" do
    Map.get(@code_map, raw, :unknown)
  end

  defp resolve_code(status, _raw) do
    Map.get(@status_map, status, :unknown)
  end

  defp default_message(status) do
    case status do
      401 -> "Unauthorized"
      403 -> "Forbidden"
      404 -> "Not found"
      409 -> "Conflict"
      422 -> "Unprocessable entity"
      429 -> "Rate limit exceeded"
      500 -> "Internal server error"
      502 -> "Bad gateway"
      503 -> "Service unavailable"
      504 -> "Gateway timeout"
      _ -> "Unknown error (HTTP #{status})"
    end
  end
end
