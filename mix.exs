defmodule PhoenixFilamentAI.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/franciscpd/phoenix_filament_ai"

  def project do
    [
      app: :phoenix_filament_ai,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      name: "PhoenixFilamentAI",
      description: "A PhoenixFilament plugin for AI capabilities.",
      source_url: @source_url,
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime
      {:phoenix_filament, "~> 0.1"},
      {:phoenix_ai, "~> 0.3"},
      {:phoenix_ai_store, "~> 0.1"},
      {:nimble_options, "~> 1.1"},
      {:mdex, "~> 0.12"},
      {:makeup, "~> 1.1"},
      {:makeup_elixir, "~> 1.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:igniter, "~> 0.5"},

      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp package do
    [
      maintainers: ["Francisco Dias"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "PhoenixFilamentAI",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
