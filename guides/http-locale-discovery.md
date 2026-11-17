# HTTP Locale Discovery

This guide covers detecting the user's locale from HTTP requests, persisting it in the session, and restoring it in LiveView using the plugs provided by `localize_web`.

## Prerequisites

Add `localize_web` and a Gettext backend to your project:

```elixir
# mix.exs
def deps do
  [
    {:localize_web, "~> 1.0"},
    {:gettext, "~> 1.0"}
  ]
end
```

Define a Gettext backend if you don't already have one:

```elixir
# lib/my_app_web/gettext.ex
defmodule MyAppWeb.Gettext do
  use Gettext.Backend, otp_app: :my_app
end
```

As an alternative to standard Gettext interpolation, you can configure the backend to use [ICU MessageFormat 2](https://hexdocs.pm/localize/Localize.Gettext.Interpolation.html) for richer message formatting including plural rules, select expressions, and number/date formatting:

```elixir
defmodule MyAppWeb.Gettext do
  use Gettext.Backend,
    otp_app: :my_app,
    interpolation: Localize.Gettext.Interpolation
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
    from: [:route, :path, :query, :session, :accept_language],
    param: "locale",
    gettext: MyAppWeb.Gettext
  plug Localize.Plug.PutSession
end
```

The Localize process locale is always set via `Localize.put_locale/1`. When a `:gettext` backend (or list of backends) is provided, the locale is also set on each Gettext backend.

### How Source Priority Works

The `:from` option controls the order of locale source lookup. The example shows the default order, which applies when `:from` is omitted:

1. The locale of a localized route (e.g. `/fr/utilisateurs`) is checked first.

2. Then path parameters (e.g. `/:locale/users`).

3. Then query parameters (e.g. `?locale=fr`).

4. Then the session, which preserves the user's previous choice on pages whose URL carries no locale.

5. Finally, the accept-language header, which gives first-time visitors a sensible default.

A locale in the URL is an explicit choice, so it wins over the session and the browser. Put `:session` or `:accept_language` earlier only if a stored preference should override the URL.

The first source that yields a valid locale wins. Remaining sources are not consulted.

A source yields a locale only when what it holds matches a locale the application supports. An identifier that is valid and matches none is passed over, and the next source is consulted: `?locale=pt` where Portuguese is not supported, or `?locale=tlh`, a language CLDR has no data for. `Localize.validate_locale/1` would answer for both, with the first supported locale and with the root locale `und`, which are right for formatting and are not what the visitor asked for. The root locale is taken when it is asked for by name, as `und`.

### The :param Option

The `:param` option specifies the parameter name to look for in query, path, body, and cookie sources. The default is `"locale"`. For example, with `param: "lang"`, the plug will look for `?lang=fr` in query params or a `lang` path parameter.

### Configuring Gettext

The `:gettext` option accepts a single Gettext backend module or a list of backends:

```elixir
# Single backend
plug Localize.Plug.PutLocale, gettext: MyAppWeb.Gettext

# Multiple backends
plug Localize.Plug.PutLocale, gettext: [MyAppWeb.Gettext, MyOtherApp.Gettext]
```

When omitted, only the Localize process locale is set and no Gettext locale is configured.

The Gettext backend can use either the standard Gettext interpolation or the [Localize.Gettext.Interpolation](https://hexdocs.pm/localize/Localize.Gettext.Interpolation.html) module which supports ICU MessageFormat 2 (MF2). MF2 provides locale-aware plural rules, select expressions, and number/date formatting directly in your translation strings. See the [Localize.Message documentation](https://hexdocs.pm/localize/Localize.Message.html) for the full MF2 syntax reference.

### The Default Locale

When no source provides a locale, the `:default` option determines the fallback:

```elixir
# Use a specific locale (default is Localize.default_locale/0)
plug Localize.Plug.PutLocale, default: "en"

# Disable the fallback entirely
plug Localize.Plug.PutLocale, default: :none

# Use a custom function
plug Localize.Plug.PutLocale, default: {MyAppWeb.Locale, :resolve_default}
```

### The `vary` response header

The plug adds a `vary` response header naming each request header it read to find the locale: `accept-language` for `:accept_language`, and `cookie` for `:session` and `:cookie`. A source read before the one that decided counts too, because a value there would have changed the locale. With the default `:from` and no locale in the URL, a response carries `vary: cookie` when the session holds a locale and `vary: cookie, accept-language` when it does not; a locale found in the route, the path or the query adds none.

The header tells a shared cache which requests a stored response may be reused for. Plug's default `cache-control` is `max-age=0, private, must-revalidate`, which keeps a response out of shared caches, and there the header changes nothing.

A shared cache that honours `vary: cookie` can reuse a response only for the visitor it was made for, so it works like a private cache. To cache localized pages in a shared cache, leave `:session` and `:cookie` out of `:from` on those routes, so the plug declares `accept-language` alone:

```elixir
plug Localize.Plug.PutLocale, from: [:route, :path, :query, :accept_language]
```

Not every cache honours `vary`. Some store no response that has a `vary` other than `accept-encoding`, as [Akamai's edge servers](https://techdocs.akamai.com/property-mgr/docs/rm-vary-header) do by default, so `vary: accept-language` keeps a page out of such a cache as well. Others ignore `vary` until they are configured to honour it, as [Cloudflare](https://blog.cloudflare.com/vary-support/) does. A locale in the URL adds no `vary` and gives each language its own cache key, so it is the form every cache handles.

An application that declares how its responses vary itself turns the plug's header off with `vary: false`. The default is `true`.

```elixir
plug Localize.Plug.PutLocale, vary: false
```

One such application keeps the locale in the session and has a cache of its own in the plug pipeline. A plug that runs before the cache copies the session's locale into a request header, the cache keys on that header, and the application sends a `vary` that names it. The plug's `vary: cookie` would then only split the cache by visitor, so it is turned off. This works for a cache inside the application alone: a cache in front of the application sees the request before that header is written.

With `vary: false` the plug adds no `vary` header at all. If `:session` or `:cookie` is still in `:from` and nothing else declares it, a cache in front of the application serves one visitor's language to another.

A response that writes the session is made for one visitor, and should say so. `Localize.Plug.PutSession` writes the session when the locale it stores differs from the one already there, and a cache that stores that response answers the next visitor in the application's place: their choice of locale never reaches the application, and is lost. Send such a response with `cache-control: private`, which is Plug's default, and keep `public` for the responses that set no cookie. `Localize.Plug.PutSession.stored?/1` says whether the plug wrote the session for a request:

```elixir
def put_cache_control(conn, _options) do
  if Localize.Plug.PutSession.stored?(conn) do
    put_resp_header(conn, "cache-control", "private")
  else
    put_resp_header(conn, "cache-control", "public, max-age=60")
  end
end
```

Do not decide it from where the locale came from. A locale in the path is on every request for that page, so a page made private for that reason would never be stored.

Storing only a locale the visitor chose, with the `:from` option of `Localize.Plug.PutSession`, means a visitor who never chooses sets no cookie, and two such visitors can be served from one stored response. For those visitors the `accept-language` header goes on deciding, so a cache that matches it as written stores one response for each way a browser writes it. A cache that normalises the header before the lookup stores one for each language.

### Avoiding Localize Calls at Compile Time

Plug options in a Phoenix router pipeline are evaluated when the module compiles. This means any `Localize.*` function call in a plug option executes during `mix compile`, which forces the Localize application to boot inside the compiler's VM and load CLDR data into memory. On memory-constrained build environments (CI runners, Docker builders, Fly.io remote builders) this can cause the compilation to be killed with an out-of-memory error.

The most common pitfall is using `Localize.default_locale/0` as the `:default` option:

```elixir
# ❌ Calls Localize.default_locale() at COMPILE TIME — loads CLDR data into the compiler VM.
plug Localize.Plug.PutLocale,
  default: Localize.default_locale(),
  gettext: MyAppWeb.Gettext
```

Instead, use a static atom or string for the default. The runtime behaviour is identical — `:en` is the default locale unless configured otherwise:

```elixir
# ✅ Static value — no Localize code runs at compile time.
plug Localize.Plug.PutLocale,
  default: :en,
  gettext: MyAppWeb.Gettext
```

If you need a dynamic default that reads from application config or system environment, use an MFA tuple so evaluation is deferred to runtime (when each request is processed):

```elixir
# ✅ MFA tuple — evaluated at runtime, not compile time.
plug Localize.Plug.PutLocale,
  default: {MyAppWeb.Locale, :resolve_default},
  gettext: MyAppWeb.Gettext
```

```elixir
defmodule MyAppWeb.Locale do
  @doc """
  Returns the default locale at runtime by checking, in order:

  1. The `:default_locale` key in the `:localize` application environment.
  2. The system `LANG` environment variable (parsed to a BCP-47 tag).
  3. Falls back to `:en`.

  """
  def resolve_default do
    Application.get_env(:localize, :default_locale) ||
      parse_system_lang() ||
      :en
  end

  defp parse_system_lang do
    case System.get_env("LANG") do
      nil ->
        nil

      lang ->
        # "en_US.UTF-8" → "en-US"; "C" / "POSIX" → nil
        lang
        |> String.split(".")
        |> hd()
        |> String.replace("_", "-")
        |> case do
          "C" -> nil
          "POSIX" -> nil
          tag -> tag
        end
    end
  end
end
```

The same principle applies anywhere a `Localize.*` function appears in module attributes, `@` attributes, or macro arguments that are evaluated at compile time — use static values or MFA tuples instead.

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
defmodule MyAppWeb.LocaleResolver do
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
  from: [{MyAppWeb.LocaleResolver, :from_user}, :session, :accept_language],
  gettext: MyAppWeb.Gettext
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

### Storing only a locale the visitor chose

By default the plug stores every locale it is given, including one that was only inferred from the `accept-language` header. A first visit therefore writes the session, and its response sets a cookie. That costs more than it looks: Varnish and nginx, among others, will not store a response that sets a cookie, and from the next request on the session decides the locale, so the response varies on the cookie.

The `:from` option names the sources whose locale is stored. It takes the same names as the `:from` option of `Localize.Plug.PutLocale`, and `:default` for the locale the `:default` option supplies:

```elixir
plug Localize.Plug.PutLocale
plug Localize.Plug.PutSession, from: [:route, :path, :query, :body]
```

A locale the visitor chose, in the URL or a form, is stored. One inferred from `accept-language`, the host or the default is not, and it is inferred again on the next request. A visitor who never chooses is given no cookie by these plugs.

Leave `:route` and `:path` out as well if a visit to a localized URL should not replace a choice already stored. `Localize.Plug.PutLocale.get_locale_source/1` returns the source that decided, for a plug of your own.

The default is `:all`, which stores a locale from any source, and a connected LiveView relies on it unless the live session is given the locale another way: see [LiveView Integration](#liveview-integration).

## LiveView Integration

In LiveView, the HTTP plug pipeline runs only on the initial page load. For subsequent live navigation, the locale must be restored from the session in the `on_mount` callback:

```elixir
defmodule MyAppWeb.LocaleLive do
  def on_mount(:default, _params, session, socket) do
    _ = Localize.Plug.put_locale_from_session(session, gettext: MyAppWeb.Gettext)
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

The `put_locale_from_session/2` function reads the locale from the session (stored by `Localize.Plug.PutSession`) and sets it for both Localize and Gettext in the LiveView process. Its result is not matched on: a first visit has no locale in the session, which returns `{:error, %Localize.Plug.NoSessionLocaleError{}}`, and the process keeps the default locale.

### Localized live routes

A live navigation mounts the next LiveView over the existing socket: no plug runs, the root layout (`<html lang>`, hreflang links) is not rendered again, and `on_mount` receives the session of the page the navigation started from. Inside a plain `live_session/3`, a live navigation from `/en/video` to `/fr/vidéo` therefore renders the French route in English.

Define localized live routes with `localize_live_session/3` instead. It defines one live session per locale (`:default_en`, `:default_fr`, and so on) and adds that locale to each live session's session. LiveView performs a full page load when a navigation crosses into another live session, so switching locale reloads the page and runs the plug pipeline, while navigation within one locale stays live:

```elixir
localize_live_session :default, on_mount: [MyAppWeb.LocaleLive] do
  scope "/", MyAppWeb do
    localize do
      live "/#{locale}/video", VideoLive
      live "/#{locale}/audio", AudioLive
    end
  end
end

live_session :unlocalized, on_mount: [MyAppWeb.LocaleLive] do
  scope "/", MyAppWeb do
    live "/dashboard", DashboardLive
  end
end
```

Every route inside `localize_live_session/3` must be inside a `localize` block; keep unlocalized live routes in their own `live_session/3`. A localized `live` route defined for more than one locale outside `localize_live_session/3` produces a compile-time warning.

### When only a chosen locale is stored

A connected LiveView cannot read the `accept-language` header, so the session is the only place it can take the locale from. When `Localize.Plug.PutSession` stores only a locale the visitor chose, a visitor who has not chosen has none in the session cookie: the page renders in the locale of their browser and the LiveView then mounts in the default locale.

Give the live session `Localize.Plug.live_session_locale/1` as its `:session`. LiveView calls it with the `conn` of the request and signs the result into the page, so the locale the plug resolved reaches `on_mount` without being written to the cookie:

```elixir
live_session :unlocalized,
  on_mount: [MyAppWeb.LocaleLive],
  session: {Localize.Plug, :live_session_locale, []} do
  scope "/", MyAppWeb do
    live "/dashboard", DashboardLive
  end
end
```

`localize_live_session/3` already passes the locale of a localized route this way, so only live sessions that are not localized need it.

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
    gettext: MyAppWeb.Gettext
  plug Localize.Plug.PutSession
end
```

Note that `:route` is listed first in `:from`. This means that when a user visits a localized route (e.g. `/fr/utilisateurs`), the locale embedded in that route takes priority. The session serves as a fallback for non-localized routes, and the accept-language header provides a sensible default for first-time visitors.
