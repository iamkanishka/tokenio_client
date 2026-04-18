defmodule Tokenio.MixProject do
  @moduledoc false
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/iamkanishka/tokenio_client"

  def project do
    [
      app: :tokenio_client,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: preferred_cli_env()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Tokenio.Application, []}
    ]
  end

  defp deps do
    [
      {:finch, "~> 0.18"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      # dev / test
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:bypass, "~> 2.1", only: :test},
      {:plug, "~> 1.15", only: :test}
    ]
  end

  defp description do
    "Production-grade Elixir client for the Token.io Open Banking platform " <>
      "(Payments v2, VRP, AIS, Banks, Refunds, Payouts, Settlement, Transfers, " <>
      "Tokens, Token Requests, Account on File, Sub-TPPs, Auth Keys, Reports, " <>
      "Webhooks, Verification)."
  end

  defp package do
    [
      name: "tokenio_client",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "API Reference" => "https://reference.token.io"},
      maintainers: ["Kanishka"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Tokenio",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/project.plt"},
      flags: [:error_handling, :underspecs],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp preferred_cli_env do
    [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["test", "coveralls"]
    ]
  end
end
