# Localize Web

[![Hex.pm](https://img.shields.io/hexpm/v/localize_web.svg)](https://hex.pm/packages/localize_web)
[![License](https://img.shields.io/hexpm/l/localize_web.svg)](https://github.com/kipcole9/localize_web/blob/main/LICENSE.md)

Phoenix integration for the [Localize](https://hex.pm/packages/localize) library providing plugs for locale discovery, compile-time route localization, and HTML form helpers for localized data.

## Features

* **[Locale Discovery](https://hexdocs.pm/localize_web/http-locale-discovery.html)** — detect the user's locale from the accept-language header, query parameters, URL path, session, cookies, hostname TLD, or custom functions.

* **[Session Persistence](https://hexdocs.pm/localize_web/http-locale-discovery.html#persisting-locale-in-the-session)** — store the discovered locale in the session for subsequent requests and LiveView connections.

* **[Compile-time Route Localization](https://hexdocs.pm/localize_web/phoenix-localized-routing.html)** — translate route path segments using Gettext at compile time and generate localized routes for each configured locale.

* **[Verified Localized Routes](https://hexdocs.pm/localize_web/phoenix-localized-routing.html#verified-localized-routes-with-q)** — the `~q` sigil provides compile-time verified localized routes that dispatch to the correct translated path based on the current locale.

* **[HTML Form Helpers](https://hexdocs.pm/localize_web/localized-html-helpers.html)** — generate `<select>` tags and option lists for currencies, territories, locales, units of measure, and months with localized display names.

## Installation

Add `localize_web` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:localize_web, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Locale Discovery

Add the locale plugs to your Phoenix endpoint or router pipeline:

```elixir
plug Localize.Plug.PutLocale,
  from: [:session, :accept_language, :query, :path],
  gettext: MyApp.Gettext

plug Localize.Plug.PutSession
```

### LiveView Support

Restore the locale in your LiveView `on_mount` callback:

```elixir
def on_mount(:default, _params, session, socket) do
  {:ok, _locale} = Localize.Plug.put_locale_from_session(session, gettext: MyApp.Gettext)
  {:cont, socket}
end
```

### Localized Routes

Configure your router with localized routes:

```elixir
defmodule MyApp.Router do
  use Phoenix.Router
  use Localize.Routes, gettext: MyApp.Gettext

  localize do
    get "/pages/:page", PageController, :show
    resources "/users", UserController
  end
end
```

Provide translations in `priv/gettext/{locale}/LC_MESSAGES/routes.po` for each path segment.

### Verified Localized Routes

Use the `~q` sigil for compile-time verified localized paths:

```elixir
use Localize.VerifiedRoutes,
  router: MyApp.Router,
  endpoint: MyApp.Endpoint,
  gettext: MyApp.Gettext

# In templates:
~q"/users"
```

### HTML Helpers

Generate localized select tags in your templates:

```elixir
iex> Localize.HTML.Territory.select(:my_form, :territory, selected: :AU)
iex> Localize.HTML.Currency.select(:my_form, :currency, selected: :USD)
iex> Localize.HTML.Locale.select(:my_form, :locale, selected: "en")
```

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/localize_web).
