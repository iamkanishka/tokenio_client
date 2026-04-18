defmodule TokenioClient.HTTP.Client do
  @moduledoc """
  Internal HTTP client backed by Finch.

  Features:
  - OAuth2 client credentials with ETS token caching
  - Static bearer token support
  - Exponential backoff retry with cryptographically-random jitter
  - Structured telemetry events on every request
  - Structured `Logger` debug/warning/error output
  """

  require Logger

  alias TokenioClient.Error
  alias TokenioClient.HTTP.TokenCache

  @sandbox_url "https://api.sandbox.token.io"
  @production_url "https://api.token.io"
  @sdk_version "1.0.0"
  @user_agent "tokenio_client-elixir/#{@sdk_version}"

  @type auth :: {:oauth2, String.t(), String.t()} | {:static, String.t()}

  @type t :: %__MODULE__{
          base_url: String.t(),
          auth: auth(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          retry_wait_min: pos_integer(),
          retry_wait_max: pos_integer(),
          finch_name: atom()
        }

  defstruct [
    :base_url,
    :auth,
    timeout: 30_000,
    max_retries: 3,
    retry_wait_min: 500,
    retry_wait_max: 5_000,
    finch_name: TokenioClient.Finch
  ]

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Build a client struct from keyword options."
  @spec new(keyword()) :: t()
  def new(opts) do
    env = Keyword.get(opts, :environment, :sandbox)
    base_url = Keyword.get(opts, :base_url) || base_url_for(env)

    auth =
      case Keyword.get(opts, :static_token) do
        nil ->
          client_id = Keyword.fetch!(opts, :client_id)
          client_secret = Keyword.fetch!(opts, :client_secret)
          {:oauth2, client_id, client_secret}

        token ->
          {:static, token}
      end

    %__MODULE__{
      base_url: base_url,
      auth: auth,
      timeout: Keyword.get(opts, :timeout, 30_000),
      max_retries: Keyword.get(opts, :max_retries, 3),
      retry_wait_min: Keyword.get(opts, :retry_wait_min, 500),
      retry_wait_max: Keyword.get(opts, :retry_wait_max, 5_000),
      finch_name: Keyword.get(opts, :finch_name, TokenioClient.Finch)
    }
  end

  # ---------------------------------------------------------------------------
  # Public request helpers
  # ---------------------------------------------------------------------------

  @doc "Execute a GET request. Returns `{:ok, map}` or `{:error, Error.t()}`."
  @spec get(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(%__MODULE__{} = client, path, opts \\ []) do
    request(client, :get, path, nil, opts)
  end

  @doc "Execute a POST request."
  @spec post(t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(%__MODULE__{} = client, path, body, opts \\ []) do
    request(client, :post, path, body, opts)
  end

  @doc "Execute a PUT request."
  @spec put(t(), String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
  def put(%__MODULE__{} = client, path, body, opts \\ []) do
    request(client, :put, path, body, opts)
  end

  @doc "Execute a DELETE request."
  @spec delete(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(%__MODULE__{} = client, path, opts \\ []) do
    request(client, :delete, path, nil, opts)
  end

  @doc "Execute a raw GET, returning the binary response body and HTTP status."
  @spec get_raw(t(), String.t(), keyword()) ::
          {:ok, binary(), non_neg_integer()} | {:error, Error.t()}
  def get_raw(%__MODULE__{} = client, path, opts \\ []) do
    with {:ok, token} <- fetch_token(client) do
      do_raw(client, :get, path, nil, token, opts)
    end
  end

  # ---------------------------------------------------------------------------
  # Core request pipeline
  # ---------------------------------------------------------------------------

  @spec request(t(), atom(), String.t(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  defp request(client, method, path, body, opts) do
    with {:ok, token} <- fetch_token(client) do
      do_with_retry(client, method, path, body, token, opts, 0)
    end
  end

  defp do_with_retry(client, method, path, body, token, opts, attempt) do
    case do_http(client, method, path, body, token, opts) do
      {:ok, _} = ok ->
        ok

      {:error, %Error{status: status} = err}
      when attempt < client.max_retries and status in [429, 500, 502, 503, 504] ->
        wait_ms = jitter_backoff(attempt, client.retry_wait_min, client.retry_wait_max)

        Logger.warning(
          "[TokenioClient] Retrying #{method_label(method)} #{path} " <>
            "(attempt #{attempt + 1}/#{client.max_retries}, wait #{wait_ms}ms) — #{err.code}"
        )

        Process.sleep(wait_ms)
        do_with_retry(client, method, path, body, token, opts, attempt + 1)

      {:error, _} = err ->
        err
    end
  end

  @spec do_http(
          t(),
          :delete | :get | :post | :put,
          String.t(),
          map() | nil,
          String.t(),
          keyword()
        ) ::
          {:ok, map()} | {:error, Error.t()}
  defp do_http(client, method, path, body, token, opts) do
    url = build_url(client.base_url, path, Keyword.get(opts, :query, []))
    headers = build_headers(token, Keyword.get(opts, :extra_headers, []))
    encoded = encode_body(body)
    req = Finch.build(method, url, headers, encoded)
    meta = %{method: method, path: path}

    start = System.monotonic_time(:millisecond)

    :telemetry.execute(
      [:tokenio_client, :request, :start],
      %{system_time: System.system_time()},
      meta
    )

    case Finch.request(req, client.finch_name, receive_timeout: client.timeout) do
      {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
        elapsed = System.monotonic_time(:millisecond) - start
        stop_meta = Map.put(meta, :status, status)
        :telemetry.execute([:tokenio_client, :request, :stop], %{duration: elapsed}, stop_meta)
        Logger.debug("[TokenioClient] #{method_label(method)} #{path} → #{status} (#{elapsed}ms)")
        parse_response(status, resp_headers, resp_body)

      {:error, reason} ->
        elapsed = System.monotonic_time(:millisecond) - start
        :telemetry.execute([:tokenio_client, :request, :exception], %{duration: elapsed}, meta)

        Logger.error(
          "[TokenioClient] #{method_label(method)} #{path} failed — #{inspect(reason)}"
        )

        {:error, Error.network_error(reason)}
    end
  end

  @spec do_raw(t(), :get, String.t(), nil, String.t(), keyword()) ::
          {:ok, binary(), non_neg_integer()} | {:error, Error.t()}
  defp do_raw(client, method, path, _body, token, opts) do
    url = build_url(client.base_url, path, Keyword.get(opts, :query, []))
    headers = build_headers(token, [])
    req = Finch.build(method, url, headers, nil)

    case Finch.request(req, client.finch_name, receive_timeout: client.timeout) do
      {:ok, %Finch.Response{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body, status}

      {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
        rid = header_value(resp_headers, "x-request-id")
        retry = header_value(resp_headers, "retry-after")
        {:error, Error.from_response(status, decode_json_map(resp_body), rid, retry)}

      {:error, reason} ->
        {:error, Error.network_error(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Response parsing
  # ---------------------------------------------------------------------------

  @spec parse_response(non_neg_integer(), [{String.t(), String.t()}], binary()) ::
          {:ok, map()} | {:error, Error.t()}
  defp parse_response(status, _headers, "") when status in 200..299, do: {:ok, %{}}

  defp parse_response(status, _headers, body) when status in 200..299 do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _} -> {:ok, %{}}
      {:error, _} -> {:ok, %{"raw" => body}}
    end
  end

  defp parse_response(status, headers, body) do
    rid = header_value(headers, "x-request-id")
    retry = header_value(headers, "retry-after")
    {:error, Error.from_response(status, decode_json_map(body), rid, retry)}
  end

  # ---------------------------------------------------------------------------
  # OAuth2 token management
  # ---------------------------------------------------------------------------

  @spec fetch_token(t()) :: {:ok, String.t()} | {:error, Error.t()}
  defp fetch_token(%__MODULE__{auth: {:static, token}}), do: {:ok, token}

  defp fetch_token(%__MODULE__{auth: {:oauth2, client_id, client_secret}, base_url: base_url}) do
    TokenCache.get_or_fetch(client_id, fn ->
      fetch_oauth2_token(base_url, client_id, client_secret)
    end)
  end

  @spec fetch_oauth2_token(String.t(), String.t(), String.t()) ::
          {:ok, String.t(), pos_integer()} | {:error, Error.t()}
  defp fetch_oauth2_token(base_url, client_id, client_secret) do
    url = base_url <> "/oauth2/token"

    body =
      URI.encode_query(%{
        "grant_type" => "client_credentials",
        "client_id" => client_id,
        "client_secret" => client_secret
      })

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"accept", "application/json"},
      {"user-agent", @user_agent}
    ]

    req = Finch.build(:post, url, headers, body)

    case Finch.request(req, TokenioClient.Finch, receive_timeout: 10_000) do
      {:ok, %Finch.Response{status: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"access_token" => tok, "expires_in" => ttl}}
          when is_binary(tok) and tok != "" ->
            {:ok, tok, ttl}

          _ ->
            msg = "Invalid OAuth2 token response"
            {:error, Error.from_response(401, %{"message" => msg}, nil, nil)}
        end

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:error, Error.from_response(status, decode_json_map(resp_body), nil, nil)}

      {:error, reason} ->
        {:error, Error.network_error(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Utilities
  # ---------------------------------------------------------------------------

  @spec build_url(String.t(), String.t(), list()) :: String.t()
  defp build_url(base, path, []), do: base <> path

  defp build_url(base, path, query) do
    qs =
      query
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if qs == "", do: base <> path, else: base <> path <> "?" <> qs
  end

  @spec build_headers(String.t(), [{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  defp build_headers(token, extra) do
    [
      {"authorization", "Bearer " <> token},
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", @user_agent}
    ] ++ extra
  end

  @spec encode_body(map() | nil) :: binary() | nil
  defp encode_body(nil), do: nil
  defp encode_body(body), do: Jason.encode!(body)

  @spec header_value([{String.t(), String.t()}], String.t()) :: String.t() | nil
  defp header_value(headers, name) do
    case Enum.find(headers, fn {k, _} -> String.downcase(k) == name end) do
      {_, v} -> v
      nil -> nil
    end
  end

  @spec decode_json_map(binary()) :: map()
  defp decode_json_map(body) do
    case Jason.decode(body) do
      {:ok, m} when is_map(m) -> m
      _ -> %{}
    end
  end

  @spec base_url_for(atom()) :: String.t()
  defp base_url_for(:production), do: @production_url
  defp base_url_for(_), do: @sandbox_url

  @spec method_label(:delete | :get | :post | :put) :: String.t()
  defp method_label(method), do: method |> to_string() |> String.upcase()

  @spec jitter_backoff(non_neg_integer(), pos_integer(), pos_integer()) :: pos_integer()
  defp jitter_backoff(attempt, min_ms, max_ms) do
    cap = min(max_ms, round(min_ms * :math.pow(2, attempt + 1)))
    rand_float = :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> Kernel./(0xFFFFFFFF)
    max(min_ms, round(rand_float * cap))
  end
end
