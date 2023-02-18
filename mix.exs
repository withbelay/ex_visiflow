defmodule ExVisiflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_visiflow,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExVisiflow.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:assert_eventually, "~> 1.0.0", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.6"},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:typed_ecto_schema, "~> 0.4.1"}
    ]
  end
end
