defmodule LocalizeWeb.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :localize_web,
      version: @version,
      elixir: "~> 1.17",
      name: "Localize Web",
      description: description(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [
        plt_add_apps: ~w(gettext phoenix phoenix_live_view phoenix_html)a
      ]
    ]
  end

  defp description do
    """
    Plugs, localized routes, and HTML helpers for the Localize library.
    """
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:localize, path: "../localize"},
      {:plug, "~> 1.9"},
      {:gettext, "~> 1.0"},
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_html_helpers, "~> 1.0", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:jason, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: [:dev, :release], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]
end
