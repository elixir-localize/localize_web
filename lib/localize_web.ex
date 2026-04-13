defmodule LocalizeWeb do
  @moduledoc """
  Phoenix integration for the [Localize](https://hex.pm/packages/localize) library providing plugs, localized routes, and HTML form helpers.

  This library consolidates the functionality previously provided by `ex_cldr_plugs`, `ex_cldr_routes`, and `cldr_html` into a single package that works with the `Localize` library.

  ## Plugs

  * `Localize.Plug.PutLocale` — discovers and sets the locale from multiple request sources (query params, path, session, accept-language header, cookies, host TLD, or custom functions).

  * `Localize.Plug.PutSession` — persists the discovered locale to the session for future requests.

  * `Localize.Plug.AcceptLanguage` — standalone plug for parsing the Accept-Language header.

  * `Localize.Plug` — utility functions for setting locale from the session, useful in LiveView `on_mount` callbacks.

  ## Routes

  * `Localize.Routes` — compile-time route localization via the `localize/1` macro. Translates route path segments using Gettext at compile time.

  * `Localize.VerifiedRoutes` — localized verified routes via the `~q` sigil, providing compile-time verification of localized paths.

  ## HTML Helpers

  * `Localize.HTML` — facade module delegating to the submodules below.

  * `Localize.HTML.Currency` — generates `<select>` tags and option lists for currencies.

  * `Localize.HTML.Territory` — generates `<select>` tags and option lists for territories/countries.

  * `Localize.HTML.Locale` — generates `<select>` tags and option lists for locales.

  * `Localize.HTML.Unit` — generates `<select>` tags and option lists for units of measure.

  * `Localize.HTML.Month` — generates `<select>` tags and option lists for month names.

  """
end
