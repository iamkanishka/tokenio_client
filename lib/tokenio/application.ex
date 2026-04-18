defmodule Tokenio.Application do
  @moduledoc false

  use Application

  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  @impl Application
  def start(_type, _args) do
    children = [
      Tokenio.HTTP.TokenCache,
      {Finch, name: Tokenio.Finch, pools: finch_pools()}
    ]

    opts = [strategy: :one_for_one, name: Tokenio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @spec finch_pools() :: map()
  defp finch_pools do
    sandbox = Application.get_env(:tokenio, :sandbox_base_url, "https://api.sandbox.token.io")
    prod = Application.get_env(:tokenio, :production_base_url, "https://api.token.io")
    size = Application.get_env(:tokenio, :pool_size, 10)
    count = Application.get_env(:tokenio, :pool_count, 1)

    pool_config = [size: size, count: count]

    for url <- Enum.uniq([sandbox, prod]), into: %{} do
      uri = URI.parse(url)
      base = "#{uri.scheme}://#{uri.host}"
      {base, pool_config}
    end
  end
end
