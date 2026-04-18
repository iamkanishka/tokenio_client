defmodule Tokenio.Client do
  @moduledoc """
  Root Token.io SDK client struct.

  Obtain one via `Tokenio.new/1` and pass it to any API function.
  The struct itself is an opaque value — do not access its fields directly.
  """

  alias Tokenio.HTTP.Client, as: HTTP

  @type t :: %__MODULE__{http: HTTP.t()}

  @enforce_keys [:http]
  defstruct [:http]

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{http: HTTP.new(opts)}
  end
end
