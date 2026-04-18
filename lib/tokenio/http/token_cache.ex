defmodule Tokenio.HTTP.TokenCache do
  @moduledoc """
  ETS-backed OAuth2 token cache with TTL expiry.

  Tokens are cached per `client_id` and automatically refreshed
  60 seconds before expiry to avoid races at TTL boundaries.
  Supervised automatically by `Tokenio.Application`.
  """

  use GenServer

  @table :tokenio_token_cache
  # Refresh 60 s before the token actually expires
  @refresh_buffer_s 60

  @typep fetch_fn :: (-> {:ok, String.t(), pos_integer()} | {:error, Tokenio.Error.t()})

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Return a valid cached token for `client_id`, or call `fetch_fn` to obtain one.

  `fetch_fn` must return `{:ok, token, ttl_seconds}` on success.
  """
  @spec get_or_fetch(String.t(), fetch_fn()) ::
          {:ok, String.t()} | {:error, Tokenio.Error.t()}
  def get_or_fetch(client_id, fetch_fn) do
    case lookup(client_id) do
      {:ok, token} ->
        {:ok, token}

      :miss ->
        case fetch_fn.() do
          {:ok, token, ttl_s} ->
            store(client_id, token, ttl_s)
            {:ok, token}

          {:error, _} = err ->
            err
        end
    end
  end

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @spec init(keyword()) :: {:ok, map()}
  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec lookup(String.t()) :: {:ok, String.t()} | :miss
  defp lookup(client_id) do
    now = System.system_time(:second)

    case :ets.lookup(@table, client_id) do
      [{^client_id, token, expires_at}] when expires_at - now > @refresh_buffer_s ->
        {:ok, token}

      _ ->
        :miss
    end
  end

  @spec store(String.t(), String.t(), pos_integer()) :: true
  defp store(client_id, token, ttl_s) do
    expires_at = System.system_time(:second) + ttl_s
    :ets.insert(@table, {client_id, token, expires_at})
  end
end
