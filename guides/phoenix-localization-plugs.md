# Phoenix Localization Plugs

This guide covers setting up locale discovery and session persistence in a Phoenix application using the localization plugs provided by `localize_web`.

## Prerequisites

Add `localize_web` and a Gettext backend to your project:

```elixir
# mix.exs
def deps do
  [
    {:localize_web, "~> 0.1.0"},
    {:gettext, "~> 1.0"}
  ]
end
```

Define a Gettext backend if you don't already have one:

```elixir
# lib/my_app/gettext.ex
defmodule MyApp.Gettext do
  use Gettext.Backend, otp_app: :my_app
end
```

## Standalone Accept-Language Parsing

The simplest way to detect a user's preferred locale is from the `Accept-Language` HTTP header sent by the browser. If that is all you need, use `Localize.Plug.AcceptLanguage`:

```elixir
# lib/my_app_web/router.ex
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Localize.Plug.AcceptLanguage
end
```

The detected locale is stored in `conn.private[:localize_locale]` and can be retrieved with:

```elixir
iex> locale = Localize.Plug.AcceptLanguage.get_locale(conn)
```

By default, a warning is logged when no configured locale matches the header. This can be changed or disabled:

```elixir
plug Localize.Plug.AcceptLanguage, no_match_log_level: :debug
plug Localize.Plug.AcceptLanguage, no_match_log_level: nil
```

## Full Locale Discovery with PutLocale

For most applications, use `Localize.Plug.PutLocale` which checks multiple sources in priority order and sets the locale from the first match:

```elixir
# lib/my_app_web/router.ex
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Localize.Plug.PutLocale,
    from: [:session, :accept_language, :query, :path],
    param: "locale",
    gettext: MyApp.Gettext
  plug Localize.Plug.PutSession
end
```

The Localize process locale is always set via `Localize.put_locale/1`. When a `:gettext` backend (or list of backends) is provided, the locale is also set on each Gettext backend.

### How Source Priority Works

The `:from` option controls the order of locale source lookup. In this example:

1. The session is checked first (preserving the user's previous choice).
2. The accept-language header is checked next.
3. Then query parameters (e.g. `?locale=fr`).
4. Finally, path parameters.

The first source that yields a valid locale wins. Remaining sources are not consulted.

### The :param Option

The `:param` option specifies the parameter name to look for in query, path, body, and cookie sources. The default is `"locale"`. For example, with `param: "lang"`, the plug will look for `?lang=fr` in query params or a `lang` path parameter.

### Configuring Gettext

The `:gettext` option accepts a single Gettext backend module or a list of backends:

```elixir
# Single backend
plug Localize.Plug.PutLocale, gettext: MyApp.Gettext

# Multiple backends
plug Localize.Plug.PutLocale, gettext: [MyApp.Gettext, MyOtherApp.Gettext]
```

When omitted, only the Localize process locale is set and no Gettext locale is configured.

### The Default Locale

When no source provides a locale, the `:default` option determines the fallback:

```elixir
# Use a specific locale (default is Localize.default_locale/0)
plug Localize.Plug.PutLocale, default: "en"

# Disable the fallback entirely
plug Localize.Plug.PutLocale, default: :none

# Use a custom function
plug Localize.Plug.PutLocale, default: {MyApp.Locale, :resolve_default}
```

## All Locale Sources

Beyond the common sources shown above, `Localize.Plug.PutLocale` supports these additional sources in the `:from` list:

* `:body` — looks for the locale parameter in `conn.body_params`.

* `:cookie` — looks for the locale parameter in the request cookies.

* `:host` — extracts the top-level domain from the hostname and resolves it to a locale. For example, `example.co.uk` resolves to a UK English locale. Generic TLDs like `.com`, `.org`, and `.net` are ignored.

* `:route` — reads the locale assigned to a route by the `localize/1` macro. See the [Phoenix Localized Routing](phoenix-localized-routing.md) guide for details.

* `{Module, function}` — calls `Module.function(conn, options)` and expects `{:ok, locale}` on success.

* `{Module, function, args}` — calls `Module.function(conn, options, ...args)` and expects `{:ok, locale}` on success.

### Custom Locale Resolution Example

```elixir
defmodule MyApp.LocaleResolver do
  def from_user(conn, _options) do
    case conn.assigns[:current_user] do
      %{preferred_locale: locale} when is_binary(locale) ->
        Localize.validate_locale(locale)
      _ ->
        {:error, :no_user}
    end
  end
end

# In the router
plug Localize.Plug.PutLocale,
  from: [{MyApp.LocaleResolver, :from_user}, :session, :accept_language],
  gettext: MyApp.Gettext
```

## Persisting Locale in the Session

`Localize.Plug.PutSession` saves the discovered locale to the session so it persists across requests. It should always be placed after `Localize.Plug.PutLocale` in the plug pipeline:

```elixir
plug Localize.Plug.PutLocale, ...
plug Localize.Plug.PutSession, as: :string
```

The `:as` option controls the storage format:

* `:string` (default) — converts the locale to a string before storing. This minimizes session size at the expense of CPU time to serialize and parse on subsequent requests.

* `:language_tag` — stores the full `%Localize.LanguageTag{}` struct. This minimizes CPU time at the expense of larger session storage.

The session key is fixed to `"localize_locale"` so that downstream consumers (such as LiveView `on_mount` callbacks) can retrieve the locale without configuration.

## LiveView Integration

In LiveView, the HTTP plug pipeline runs only on the initial page load. For subsequent live navigation, the locale must be restored from the session in the `on_mount` callback:

```elixir
defmodule MyAppWeb.LocaleLive do
  def on_mount(:default, _params, session, socket) do
    {:ok, _locale} = Localize.Plug.put_locale_from_session(
      session,
      gettext: MyApp.Gettext
    )
    {:cont, socket}
  end
end
```

Then attach it in your router:

```elixir
live_session :default, on_mount: [MyAppWeb.LocaleLive] do
  scope "/", MyAppWeb do
    live "/dashboard", DashboardLive
  end
end
```

The `put_locale_from_session/2` function reads the locale from the session (stored by `Localize.Plug.PutSession`) and sets it for both Localize and Gettext in the LiveView process.

## Accessing the Locale in Controllers and Views

After the plug pipeline runs, the locale is available in several ways:

```elixir
# From the conn (set by PutLocale)
locale = Localize.Plug.PutLocale.get_locale(conn)

# From the Localize process dictionary
locale = Localize.get_locale()
```

## Putting It All Together

A typical Phoenix application plug pipeline for full localization support:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug Localize.Plug.PutLocale,
    from: [:route, :session, :accept_language],
    gettext: MyApp.Gettext
  plug Localize.Plug.PutSession
end
```

Note that `:route` is listed first in `:from`. This means that when a user visits a localized route (e.g. `/fr/utilisateurs`), the locale embedded in that route takes priority. The session serves as a fallback for non-localized routes, and the accept-language header provides a sensible default for first-time visitors.
