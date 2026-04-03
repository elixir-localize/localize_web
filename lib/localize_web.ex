defmodule LocalizeWeb do
  @moduledoc """
  Plugs, localized routes, and HTML helpers for the Localize library.

  This library provides Phoenix integration for the `Localize` library,
  consolidating the functionality of `ex_cldr_plugs`, `ex_cldr_routes`,
  and `cldr_html` into a single package.

  ## Plugs

  * `Localize.Plug.PutLocale` - discovers and sets the locale from
    multiple request sources (query params, path, session, accept-language
    header, cookies, host TLD, or custom functions).

  * `Localize.Plug.PutSession` - persists the discovered locale to the
    session for future requests.

  * `Localize.Plug.AcceptLanguage` - standalone plug for parsing the
    Accept-Language header.

  * `Localize.Plug` - utility functions for setting locale from the
    session, useful in LiveView `on_mount` callbacks.

  ## Routes

  * `Localize.Routes` - compile-time route localization via the
    `localize/1` macro.

  * `Localize.VerifiedRoutes` - localized verified routes via the
    `~q` sigil.

  ## HTML Helpers

  * `Localize.HTML` - facade module delegating to submodules.

  * `Localize.HTML.Currency` - currency select helpers.

  * `Localize.HTML.Territory` - territory/country select helpers.

  * `Localize.HTML.Locale` - locale select helpers.

  * `Localize.HTML.Unit` - unit of measure select helpers.

  * `Localize.HTML.Month` - month name select helpers.

  """
end
