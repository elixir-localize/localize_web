defmodule LocalizeWeb.MixProject do
  use Mix.Project

  @version "0.7.0"

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
      aliases: aliases(),
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
      links: links(),
      files: ~w(lib priv guides mix.exs README.md LICENSE.md CHANGELOG.md)
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-localize/localize_web",
      "Readme" => "https://github.com/elixir-localize/localize_web/blob/v#{@version}/README.md",
      "Changelog" =>
        "https://github.com/elixir-localize/localize_web/blob/v#{@version}/CHANGELOG.md"
    }
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
        "guides/localized-html-helpers.md",
        "guides/mf2-messages-in-heex.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/http-locale-discovery.md",
          "guides/phoenix-localized-routing.md",
          "guides/localized-html-helpers.md",
          "guides/mf2-messages-in-heex.md"
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
          Localize.HTML.Month,
          Localize.HTML.Message
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
      {:localize, localize_dep_spec()},
      {:plug, "~> 1.9"},
      {:gettext, "~> 1.0"},
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:jason, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: [:dev, :release], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ] ++ maybe_json_polyfill()
  end

  # In a sibling checkout, develop against the local copy of `localize`
  # so unreleased APIs (e.g. `Localize.Message.Sigils.t/1` helpers) are
  # available. Falls back to the published version for users without
  # the sibling checkout.
  defp localize_dep_spec do
    sibling = Path.expand("../localize", __DIR__)

    if File.dir?(sibling) do
      [path: sibling, override: true]
    else
      "~> 0.33"
    end
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

  # Ensure CLDR locale data for the locales referenced in tests is
  # present before the suite runs. The download is a no-op when the
  # cache is already populated, so the alias is cheap on warm
  # developer machines.
  defp aliases do
    [
      test: ["localize.download_locales", "test"]
    ]
  end
end
