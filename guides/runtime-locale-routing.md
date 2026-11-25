# Runtime locale routing

Many sites name the language in the first segment of the address and leave it out for the primary language: `/about` in English and `/fr/about` in French. This guide shows how to serve such addresses with the locale decided at runtime, so a language added to a site, or a site added to a platform, needs no new route and no recompile. It covers the rules of a locale prefix, an ordinary Phoenix router with LiveView, a CMS that answers every address with one catch-all route, live navigation, and building addresses for links, language switchers and `hreflang` annotations.

## Runtime prefixes and translated routes

`localize_web` offers two ways to put the language in the address:

* **Translated routes** — `Localize.Routes.localize/1` declares a route for each locale at compile time, with the path segments translated by Gettext: `/users` in English and `/utilisateurs` in French. Choose it when the segments themselves must be in the page's language. See the [Phoenix localized routing guide](phoenix-localized-routing.md).

* **Runtime prefixes** — this guide. The language is a prefix on an otherwise unchanged path, and it is a value read at runtime rather than a route of its own. Choose it when the locales are known only at runtime, such as a site whose languages are kept in a database, or when an optional prefix for the primary language is wanted.

The pieces of the runtime approach are:

* **`Localize.Routes.Prefix`** — the rules, as functions of a path: `split/2`, `path/3`, `target/3` and `localized_path/3`.

* **`Localize.Plug.PutLocale`** with the `:path_prefix` source — reads the locale from the first segment of the path.

* **`Localize.Plug.LocalePrefix`** — applies a URL mode to each HTTP request: it redirects and answers `404`.

* **`Localize.Routes.locale_prefix/2`** — declares an ordinary router's routes as written and under a `/:locale` parameter.

* **`Localize.Live.LocalePrefix`** — applies the same rules on each live navigation.

## URL modes

A site chooses one of two modes, or one for each of its sites:

* **`:prefix_others`** — the default locale has no prefix. `/about` is the default locale's page and `/fr/about` the French one. `/en/about`, where English is the default, is redirected to `/about` with a `301`, so each page has one address in each language.

* **`:prefix_all`** — every locale has a prefix. `/about` is redirected with a `302` to the visitor's language, found from the session or the `accept-language` header, or to the default locale for a visitor with neither, such as a crawler.

The decision is `Localize.Routes.Prefix.target/3`'s, the same for an HTTP request and a live navigation:

```elixir
iex> options = [default: :en, supported: ["en", "fr", "de"]]
iex> Localize.Routes.Prefix.target("/en/about?page=2", :fr, options)
{:redirect, "/about?page=2", 301}
iex> Localize.Routes.Prefix.target("/about", :fr, [mode: :prefix_all] ++ options)
{:redirect, "/fr/about", 302}
iex> {:serve, locale} = Localize.Routes.Prefix.target("/about", :fr, options)
iex> locale.cldr_locale_id
:en
```

Under `:prefix_others` the address alone decides, which is why `/about` is served in English even to a visitor whose session holds French: the address names the default locale.

A prefix must name a supported locale exactly, ignoring case and taking `_` for `-`. It is never matched by closeness, so `/fr-ca/about` is not French where only `fr` is supported, and a page whose slug resembles a language is never taken for one:

```elixir
iex> {:ok, {locale, rest}} = Localize.Routes.Prefix.split("/ZH_HANT/blog", ["en", "zh-Hant"])
iex> {locale.cldr_locale_id, rest}
{:"zh-Hant", "/blog"}
iex> Localize.Routes.Prefix.split("/fr-ca/about", ["en", "fr"])
{:ok, {nil, "/fr-ca/about"}}
```

## An ordinary router

Two plugs go in the pipeline. `Localize.Plug.PutLocale` finds the locale, from the prefix first, and `Localize.Plug.LocalePrefix` applies the mode, using `PutLocale`'s supported locales, default locale and parameter name:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Localize.Plug.PutLocale,
    from: [:path_prefix, :session, :accept_language],
    gettext: MyAppWeb.Gettext
  plug Localize.Plug.LocalePrefix, mode: :prefix_all
end
```

`Localize.Routes.locale_prefix/2` declares the routes of its block twice, as written and in a `scope "/:locale"`. Placed inside the live session, both copies share it, so a LiveView connects to `/about` and `/fr/about` and navigates live between them:

```elixir
import Localize.Routes, only: [locale_prefix: 1]

scope "/", MyAppWeb do
  pipe_through :browser

  live_session :default,
    on_mount: [{Localize.Live.LocalePrefix, gettext: MyAppWeb.Gettext}],
    session: {Localize.Live.LocalePrefix, :session, []} do
    locale_prefix do
      live "/", HomeLive
      live "/about", AboutLive
      live "/products/:id", ProductLive
    end
  end
end
```

`~p"/about"` and `~p"/#{locale}/about"` are both verified routes. The locale is a parameter, so a language added at runtime needs no route.

Phoenix answers a request with the first route that matches it, and a parameter matches any segment, so the macro checks the block when the router compiles:

* **A route whose first segment is dynamic is refused**, such as `/:category/:slug`: its copy `/:locale/:category/:slug` overlaps it, and `/fr/shoes` would be read as either. Give it a literal first segment, or declare it outside the block.

* **`forward`, `live_session` and nested blocks are refused**, since they cannot be declared twice.

* **A route after the block that a copy reaches first is warned of**, naming both and a path they share. With `/about` in the block, a later `get "/help/about"` is never reached for `/help/about`, which `/:locale/about` matches. Declare such routes before the block.

One overlap cannot be checked: with `/` in the block, its copy `/:locale` matches every path of one segment, so a mistyped `~p"/abuot"` is not reported as an unknown route.

A prefixed copy also matches a first segment that is not a locale, such as `/blog/about`. `Localize.Plug.LocalePrefix` answers it with a `404`: it raises `Localize.Plug.LocalePrefix.NotFoundError`, whose `plug_status` is `404`, so Phoenix renders the application's not-found page, as for an address no route matches.

## A CMS with a catch-all route

A CMS answers every address with one route and finds the page from the path, so it needs no `locale_prefix/2`: `/*path` already matches `/fr/about`. Its languages and URL mode are often kept per site, so the settings are functions of the request:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Localize.Plug.PutLocale,
    from: [:path_prefix, :session, :accept_language],
    supported: {MyApp.Sites, :locales}
  plug Localize.Plug.LocalePrefix,
    mode: {MyApp.Sites, :url_mode},
    default: {MyApp.Sites, :default_locale},
    exists?: {MyApp.Pages, :published?}
end

scope "/", MyAppWeb do
  pipe_through :browser

  live_session :pages,
    on_mount: [Localize.Live.LocalePrefix],
    session: {Localize.Live.LocalePrefix, :session, []} do
    live "/*path", PageLive
  end
end
```

`Localize.Plug.LocalePrefix` calls its functions with a `Localize.Routes.Request`, which holds the host, the path, the session and the assigns. `Localize.Live.LocalePrefix` calls `:exists?` with one built from the navigation, so a function that finds the site from the host works for both. `:exists?` is consulted for a `302` under `:prefix_all`: a page with no edition in the visitor's language is redirected to the default locale's address instead.

```elixir
defmodule MyApp.Sites do
  alias Localize.Routes.Request

  def url_mode(%Request{host: host}) do
    site(host).url_mode
  end

  def default_locale(%Request{host: host}) do
    site(host).default_locale
  end

  # PutLocale's own :supported function takes the conn and its options.
  def locales(%Plug.Conn{host: host}, _options) do
    site(host).locales
  end

  defp site(host) do
    MyApp.Repo.get_by(MyApp.Site, host: host) || MyApp.Site.default()
  end
end

defmodule MyApp.Pages do
  def published?(%Localize.Routes.Request{host: host}, path, locale) do
    MyApp.Repo.exists?(MyApp.Pages.edition_query(host, path, locale))
  end
end
```

The LiveView takes the prefix off the path it is given to find the page, with `Localize.Routes.Prefix.split/2`:

```elixir
def handle_params(_params, uri, socket) do
  settings = Localize.Live.LocalePrefix.get_settings(socket)
  %URI{path: path} = URI.parse(uri)

  case Localize.Routes.Prefix.split(path, settings.supported) do
    {:ok, {_locale, page_path}} -> {:noreply, assign_page(socket, page_path)}
    {:error, _exception} -> {:noreply, assign_page(socket, "/")}
  end
end
```

## Live navigation

A `push_patch` or a `navigate` within one live session reaches `handle_params/3` and not the router's pipeline, so `Localize.Live.LocalePrefix` makes the plug's decision again for each navigation: it sets the locale a prefix names, for Localize and Gettext, or pushes the redirect the plug would have answered with.

The hook takes no mode or locales of its own. `Localize.Live.LocalePrefix.session/1`, given as the live session's `:session`, signs the locale `PutLocale` set and the settings `LocalePrefix` resolved into the page, without writing the session cookie. A site whose settings are functions of the request resolves them once, when the page is requested, and each navigation uses them. It replaces `Localize.Plug.live_session_locale/1`, whose locale it includes.

Changing the locale changes no assign, and a LiveView re-renders only what depends on assigns that changed. Link to the same page in another language with `navigate`, which mounts the LiveView again in that language, rather than patching to it.

A navigation to a locale parameter that names no supported locale raises `Localize.Plug.LocalePrefix.NotFoundError` in the hook. The LiveView ends, the browser loads the address over HTTP, and the plug answers it with a `404`.

## Building addresses

`Localize.Routes.Prefix.path/3` gives a path's address in a locale, adding, dropping or replacing the prefix under the mode:

```elixir
iex> options = [default: :en, supported: ["en", "fr", "de"]]
iex> Localize.Routes.Prefix.path("/about", :fr, options)
{:ok, "/fr/about"}
iex> Localize.Routes.Prefix.path("/fr/about", :en, options)
{:ok, "/about"}
iex> Localize.Routes.Prefix.path("/fr/about?page=2", :de, [mode: :prefix_all] ++ options)
{:ok, "/de/about?page=2"}
```

In a template, `Localize.Routes.Prefix.localized_path/3` gives a verified route's address in the request's locale, or another, by the settings the plug or the hook resolved, so a site whose settings are functions of the request repeats none of them. It returns a string; a path it cannot localize is logged and returned as it is.

```elixir
<.link navigate={Localize.Routes.Prefix.localized_path(@socket, ~p"/about")}>About</.link>
<.link href={Localize.Routes.Prefix.localized_path(@conn, ~p"/about", :de)}>Deutsch</.link>
```

Outside a request, it takes the settings as a map:

```elixir
iex> settings = %{mode: :prefix_others, default: "en", supported: ["en", "fr", "de"]}
iex> Localize.Routes.Prefix.localized_path(settings, "/about", :fr)
"/fr/about"
```

A path that begins with the request's script name, as a verified route does in a mounted application, keeps it in front of the prefix: `/app/about` in French is `/app/fr/about`.

### Language switchers and alternates

A page's address in each of its languages is the map of locale to URL that `Localize.HTML.LanguageSwitcher` and `Localize.HTML.Hreflang` take:

```elixir
iex> settings = %{mode: :prefix_others, default: "en", supported: ["en", "fr", "de"]}
iex> urls =
...>   Map.new(["en", "fr", "de"], fn locale ->
...>     {locale, Localize.Routes.Prefix.localized_path(settings, "/about", locale)}
...>   end)
iex> urls
%{"de" => "/de/about", "en" => "/about", "fr" => "/fr/about"}
iex> {:ok, entries} = Localize.HTML.LanguageSwitcher.links(urls, current: :fr)
iex> Enum.map(entries, &{&1.name, &1.url, &1.current?})
[{"Deutsch", "/de/about", false}, {"English", "/about", false}, {"Français", "/fr/about", true}]
```

Render the switcher with `navigate`, so a LiveView remounts in the chosen language:

```elixir
<Localize.HTML.LanguageSwitcher.language_switcher urls={@urls} navigate label="Language" />
```

`hreflang` annotations need absolute URLs; prefix each path with the site's origin before passing the map to `Localize.HTML.Hreflang.links/2`. Under `:prefix_all`, the unprefixed address, which redirects each visitor to their language, is the natural `x-default`.

## Caching

A `301` depends on the address alone, and a browser or shared cache may keep it. A `302` depends on the visitor, and carries the `vary` header `Localize.Plug.PutLocale` adds for each source it read: `cookie` for the session and `accept-language` for the header. See [the `vary` response header](http-locale-discovery.md#the-vary-response-header).

Under `:prefix_others` the address alone decides the locale, so `PutLocale`'s `:from` needs only `:path_prefix`. A source listed after it is read on every request with no prefix and adds a `vary` that the response, served in the default locale, does not need.
