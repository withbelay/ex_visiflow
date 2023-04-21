defmodule WorkflowEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :workflow_ex,
      version: "0.1.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:assert_eventually, "~> 1.0.0", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.9"},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:opentelemetry_api, "~> 1.2"},
      {:typed_ecto_schema, "~> 0.4.1"}
    ]
  end
end
