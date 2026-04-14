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
      source_url: "https://github.com/elixir-localize/localize_web",
      package: package(),
      docs: docs(),
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

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/elixir-localize/localize_web",
        "Changelog" => "https://github.com/elixir-localize/localize_web/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv guides mix.exs README.md LICENSE.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      formatters: ["html", "markdown"],
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/http-locale-discovery.md",
        "guides/phoenix-localized-routing.md",
        "guides/localized-html-helpers.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/http-locale-discovery.md",
          "guides/phoenix-localized-routing.md",
          "guides/localized-html-helpers.md"
        ]
      ],
      groups_for_modules: [
        Plugs: [
          Localize.Plug,
          Localize.Plug.PutLocale,
          Localize.Plug.PutSession,
          Localize.Plug.AcceptLanguage,
          Localize.AcceptLanguage
        ],
        Routes: [
          Localize.Routes,
          Localize.VerifiedRoutes,
          Localize.Routes.LocalizedHelpers
        ],
        "HTML Helpers": [
          Localize.HTML,
          Localize.HTML.Currency,
          Localize.HTML.Territory,
          Localize.HTML.Locale,
          Localize.HTML.Unit,
          Localize.HTML.Month
        ]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "Localize.AcceptLanguage"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:localize, "~> 0.4"},
      {:plug, "~> 1.9"},
      {:gettext, "~> 1.0"},
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_html_helpers, "~> 1.0", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:jason, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: [:dev, :release], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ] ++ maybe_json_polyfill()
  end

  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0"}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]
end
