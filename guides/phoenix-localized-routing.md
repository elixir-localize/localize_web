# Phoenix Localized Routing

This guide covers compile-time route localization using the `localize/1` macro and verified localized routes using the `~q` sigil.

## Prerequisites

Localized routing requires a Gettext backend. Path segments are translated at compile time using `Gettext.dgettext/3` with the `"routes"` domain. Only locales defined in the Gettext backend can have localized routes.

```elixir
# mix.exs
def deps do
  [
    {:localize_web, "~> 0.1.0"},
    {:gettext, "~> 1.0"}
  ]
end
```

```elixir
# lib/my_app/gettext.ex
defmodule MyApp.Gettext do
  use Gettext.Backend, otp_app: :my_app
end
```

## Router Configuration

Add `use Localize.Routes` to your router alongside `use Phoenix.Router`:

```elixir
defmodule MyApp.Router do
  use Phoenix.Router
  use Localize.Routes, gettext: MyApp.Gettext

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug Localize.Plug.PutLocale,
      from: [:route, :session, :accept_language],
      gettext: MyApp.Gettext
    plug Localize.Plug.PutSession
  end

  scope "/", MyApp do
    pipe_through :browser

    localize do
      get "/pages/:page", PageController, :show
      resources "/users", UserController
    end
  end
end
```

The `localize/1` macro wraps standard Phoenix route macros (`get`, `post`, `put`, `patch`, `delete`, `resources`, `live`, etc.) and generates a localized version of each route for every locale in the Gettext backend.

Include `:route` in the `Localize.Plug.PutLocale` `:from` list so that the locale embedded in a matched route is automatically set for the request.

## Setting Up Route Translations

Route translations use the Gettext domain `"routes"`. Create a PO file for each locale under `priv/gettext/{locale}/LC_MESSAGES/routes.po`:

```
# priv/gettext/fr/LC_MESSAGES/routes.po
msgid ""
msgstr ""
"Language: fr\n"

msgid "pages"
msgstr "pages_fr"

msgid "users"
msgstr "utilisateurs"
```

```
# priv/gettext/de/LC_MESSAGES/routes.po
msgid ""
msgstr ""
"Language: de\n"

msgid "pages"
msgstr "seiten"

msgid "users"
msgstr "benutzer"
```

Each `msgid` is a single path segment (the text between `/` characters in the route path). After compilation, the router contains routes for each locale:

* `/pages/:page` (English, the default)
* `/pages_fr/:page` (French)
* `/seiten/:page` (German)

If a translation is empty or missing for a given segment, the original English segment is used for that locale.

## Interpolating Locale Data into Paths

Route paths can include locale interpolations using the `#{}` syntax. This is useful for URL schemes that embed the locale as a path prefix:

```elixir
localize do
  get "/#{locale}/pages/:page", PageController, :show
  get "/#{language}/help", HelpController, :index
  get "/#{territory}/store", StoreController, :index
end
```

The supported interpolations are:

* `locale` — the CLDR locale name (e.g., `en`, `fr`, `de`).

* `language` — the language code (e.g., `en`, `fr`, `de`).

* `territory` — the territory code (e.g., `us`, `fr`, `de`).

Interpolation is resolved at compile time. The first example above generates routes like `/en/pages/:page`, `/fr/pages_fr/:page`, and `/de/seiten/:page`.

## Localizing a Subset of Locales

By default, `localize/1` generates routes for all locales known to the Gettext backend. To restrict to specific locales, pass a list:

```elixir
localize [:en, :fr] do
  resources "/comments", CommentController
end
```

A single locale also works:

```elixir
localize "fr" do
  get "/chapters/:page", PageController, :show, as: "chap"
end
```

## Supported Route Macros

The `localize` macro supports all standard Phoenix route macros:

* `get`, `post`, `put`, `patch`, `delete`, `options`, `head`, `connect`
* `resources` (including nested resources)
* `live`

## Nested Resources

Nested resources are fully supported. Each level is localized independently:

```elixir
localize do
  resources "/users", UserController do
    resources "/faces", FaceController, except: [:delete] do
      resources "/#{locale}/visages", VisageController
    end
  end
end
```

## Localized Route Helpers

A `LocalizedHelpers` module is generated at compile time. If your router is `MyApp.Router`, the helpers are at `MyApp.Router.LocalizedHelpers`.

The helper functions automatically dispatch to the correct locale-specific route based on the current locale:

```elixir
iex> import MyApp.Router.LocalizedHelpers
iex> Localize.put_locale("fr")
iex> page_path(conn, :show, "intro")
"/pages_fr/intro"

iex> Localize.put_locale("de")
iex> page_path(conn, :show, "intro")
"/seiten/intro"
```

The same helper name works for all locales. The current process locale determines which translated path is returned.

To disable helper generation:

```elixir
use Localize.Routes, gettext: MyApp.Gettext, helpers: false
```

### Static and URL Helpers

The `LocalizedHelpers` module also delegates to the standard Phoenix helpers:

* `path/2` — generates the path including any necessary prefix.
* `url/1` — generates the base URL without path information.
* `static_path/2`, `static_url/2`, `static_integrity/2` — static asset helpers.

## Generating hreflang Links

The generated helpers include `*_links` functions that produce a map of locale-to-URL pairs. These are used to build `<link rel="alternate" hreflang="...">` tags for SEO:

```elixir
iex> url_map = MyApp.Router.LocalizedHelpers.page_links(conn, :show, "intro")
%{"en" => "http://localhost/pages/intro", "fr" => "http://localhost/pages_fr/intro"}

iex> MyApp.Router.LocalizedHelpers.hreflang_links(url_map)
{:safe, ...}  # Generates <link href="..." rel="alternate" hreflang="..."/> tags
```

Place the output of `hreflang_links/1` in your layout's `<head>` section to help search engines discover the localized versions of your pages.

## Verified Localized Routes with ~q

For compile-time verified routes, use `Localize.VerifiedRoutes` instead of `Phoenix.VerifiedRoutes`:

```elixir
# lib/my_app_web.ex
defp html_helpers do
  quote do
    use Localize.VerifiedRoutes,
      router: MyApp.Router,
      endpoint: MyApp.Endpoint,
      gettext: MyApp.Gettext
  end
end
```

Then use the `~q` sigil in templates and controllers:

```elixir
<.link navigate={~q"/users"}>Users</.link>
```

The `~q` sigil generates a `case` expression at compile time that dispatches to the correct localized `~p` path based on the current locale:

```elixir
# ~q"/users" compiles to something like:
case Localize.get_locale().cldr_locale_id do
  :de -> ~p"/benutzer"
  :en -> ~p"/users"
  :fr -> ~p"/utilisateurs"
end
```

The `~p` sigil remains available for non-localized routes.

### Using ~q with url/1

The `url/1`, `url/2`, and `url/3` functions work with `~q` to produce full URLs:

```elixir
iex> Localize.put_locale("fr")
iex> url(~q"/users")
"http://localhost/utilisateurs"
```

### Locale Interpolation in ~q

The `~q` sigil supports the same locale interpolations as the `localize` macro:

```elixir
~q"/#{locale}/pages/intro"
# Produces "/fr/pages_fr/intro" when the locale is :fr
```

## Inspecting Localized Routes

Localized routes are stored in a `LocalizedRoutes` submodule. You can inspect them with the `phx.routes` mix task:

```bash
mix phx.routes MyApp.Router.LocalizedRoutes
```

This shows all generated localized routes with their paths, verbs, and controller actions.

## Acknowledgements

> #### Attribution {: .info}
>
> `Localize.Routes` is based on `ex_cldr_routes` which was inspired by the work originally done by [Bart Otten](https://github.com/BartOtten) on `PhxAltRoutes` — which has evolved to the much enhanced [Routex](https://hex.pm/packages/routex). Users seeking a more comprehensive and extensible localized routing solution should consider [Routex](https://hex.pm/packages/routex) as an alternative to `Localize.Routes`.
