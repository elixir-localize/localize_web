# Runtime locale routing

**Status:** implemented (v1.5.0), 2026-11-25

A design for an optional locale prefix handled at runtime: `/about` in the default language beside `/fr/about`, with redirects between the forms, the same decision on a live navigation, and helpers to build the addresses. It serves two kinds of application: one with an ordinary router that wants every language without a copy of its routes per language, and one whose pages are data, such as a CMS answering every address with one catch-all route and choosing its languages per site. `mishka_cms_core` (`MishkaCmsCore.Runtime.Plugs.LanguagePlug`, at `a86940a`) is the second kind and the source of the requirements. Nothing here is built yet; the target is the release after 1.5.0.

## The problem

`Localize.Routes` localizes routes at compile time. Each route is generated once per Gettext locale with its path segments translated, and `#{locale}` interpolation puts the locale in the path for every language, the default included. There is no form in which the default language is unprefixed, and nothing redirects `/en/about` to `/about`, or an address with no language to the visitor's. An application that wants `/about` and `/fr/about` writes its routes twice and its redirects by hand. One whose addresses are data cannot use compile-time routes at all.

1.5.0 gives both the parts that discover and present a locale: the `:path_prefix` source and a `:supported` function of the request, `accept-language` matched against that list, `:session_key`, `Localize.HTML.Document` for `<html lang dir>` across live navigation, and `Localize.HTML.Hreflang` and `Localize.HTML.LanguageSwitcher` built from a map of locale to URL. What is missing is the routing: deciding whether to answer an address or send the visitor to another form of it, building those addresses, and making the same decision on a live navigation, where no plug runs.

## Compile time, runtime and verified routes

Phoenix's verified routes check a path against the router when the application compiles, which is worth keeping. They need the routes to be known then, and that is where the line between compile-time and runtime routing falls:

* **A translated path segment** (`/produits` for `/products`) changes the path, so it must be a route, made at compile time. `Localize.Routes` does this with Gettext, and so does [Routex](https://hex.pm/packages/routex), which also serves the default locale unprefixed and makes `~p` branch to the current locale's route. This plan does not compete with either.

* **A locale prefix** wraps a path without changing it. Declared once as a `:locale` parameter in front of the routes, it serves every language with one set of route definitions, `~p"/about"` and `~p"/#{locale}/about"` stay verified, and a language added at runtime needs no new route. This is the part that can be done at runtime without giving up verified routes, and it is this plan's subject.

* **A page whose path is data**, a CMS page, has no route to verify. Its application resolves the path itself and needs the prefix rules, the redirects and the address helpers, but not the router integration.

So the plan has a router macro for ordinary routers, a layer of rules and helpers that every application uses, and a hook for live navigation. Removing the prefix before the router, the first idea for ordinary routers, does not work with LiveView; see "Spike: stripping the prefix" below.

## Prior art

* **Django** routes with `i18n_patterns(..., prefix_default_language=False)` and redirects with its locale middleware: the prefix is optional for the default language.

* **next-intl** has `localePrefix: "as-needed"` and `"always"`, and **Nuxt i18n** the strategies `prefix_except_default` and `prefix`: the same two modes.

* **Routex** makes localized routes at compile time from CLDR, Gettext or Fluent locales, serves its `default_locale` at the top-level routes, detects the locale at runtime from the path, session, `accept-language` and others, and has a LiveView `handle_params` hook. Its documentation describes no redirects between the forms of an address and nothing for paths that are data, and it integrates with `ex_cldr` rather than Localize.

## Requirements

The core:

1. **The language is the first path segment only**, and only when it names one of the supported locales exactly (the `:path_prefix` rule).

2. **Two URL modes:**

   * `:prefix_others` — the default language has no prefix. `/about` is answered in the default language, `/fr/about` in French, and `/en/about`, where English is the default, is redirected to `/about` with a `301`.

   * `:prefix_all` — every language has a prefix. `/about` is redirected with a `302` to the visitor's language, `/fr/about`.

3. **The visitor's language for a `302`** is found as `Localize.Plug.PutLocale` finds it, by its `:from` sources: the session, then `accept-language` if the application lists it, then the default. A crawler, with neither, lands on the default language and finds the others through `hreflang`.

4. **The query string is kept** on a redirect.

5. **The same decision on a live navigation.** A `navigate` or `push_patch` within one live session reaches `handle_params/3`, not a plug, and is answered by the same rules.

6. **Caching is correct.** A `301` depends on the address alone and may be cached. A `302` depends on the session or `accept-language`, and carries the `vary` of the sources consulted.

7. **Addresses are built by the same rules**, for alternates, the language switcher, sitemaps and canonical links.

8. **Options are values by default and functions where needed.** The mode, the default locale and the supported locales are static for most applications and a function of the request for a site among many.

Optional, for applications whose paths are data:

9. **A redirect may be made only to an address that exists**, falling back to the default language's address, as Mishka does for a page with no edition in the remembered language. The test is the application's.

Out of scope: translated path segments (`Localize.Routes`, Routex) and a page's slug in each language, which is the application's data and from which it builds its map of locale to URL.

## Options

* **Fold the redirects into `Localize.Plug.PutLocale`.** It would mix discovering a locale with routing policy, in a plug used where no redirects are wanted. Rejected.

* **Rules and helpers only, with no router integration.** Enough for a CMS, but an ordinary router would still need a route per language for every page. Rejected as the whole answer; kept as the core.

* **Strip the prefix before the router, on top of shared rules, with a hook for live navigation.** One set of routes and verified routes kept, but a LiveView cannot connect to a stripped address. Rejected after the spike.

* **Declare each route plain and under a `/:locale` parameter, from one definition, on top of shared rules, with a hook for live navigation.** Serves both kinds of application, works with LiveView's connect, patch and navigation, keeps verified routes, and takes languages added at runtime. Chosen.

* **Leave it to applications.** Each writes the rules again, and the places it goes wrong, exact prefix matching, `301` against `302` and `vary`, are the ones a library should settle. Rejected.

## Decision

### `Localize.Routes.Prefix` — the rules and helpers

Functions of a path with no `conn`, used by every layer:

* **`split(path, supported)`** returns `{locale, rest}` when the first segment names a supported locale exactly, and `{nil, path}` otherwise. The `:path_prefix` source uses the same function.

* **`path(path, locale, options)`** returns the address of `path` in `locale` under `:mode` and `:default`, adding, dropping or replacing the prefix: `path("/about", :fr, mode: :prefix_others, default: :en)` is `"/fr/about"`, and `path("/fr/about", :en, ...)` is `"/about"`.

* **`target(path, locale, options)`** returns `{:serve, locale}` or `{:redirect, path, 301 | 302}` under `:mode` and `:default`, with an optional `:exists?` test. The decision comes from the path: a prefixed path is served in the locale it names, or redirected with a `301` when that is the default under `:prefix_others`, and an unprefixed path is served in the default locale under `:prefix_others`, or redirected with a `302` to the visitor's `locale` under `:prefix_all`. The source of the visitor's locale is not needed for the decision, only for the `vary` of a `302`, which is the plug's. `:exists?` is called with the path without its prefix and the locale.

`localized_path/3` composes a verified route with `path/3`, so `~p"/about"` is checked at compile time and given the current locale's prefix at runtime: `localized_path(@conn, ~p"/about")`. It reads the settings `Localize.Plug.LocalePrefix` resolved for the request, or those the live hook puts on the socket, so a site whose settings are functions of the request repeats none of them, and a third argument gives the address in another locale.

### `Localize.Plug.LocalePrefix` — on a request

Runs after `Localize.Plug.PutLocale`, which has resolved the locale from `:path_prefix` and the other sources, and applies the mode:

* Under `:prefix_others`, a locale found by `:path_prefix` that is the default is redirected to the address without the prefix, with a `301`.

* Under `:prefix_all`, a locale found by any other source is redirected to the address with its prefix, with a `302`, or, when `:exists?` is given and does not hold, to the default language's address.

* A `:locale` path parameter that names no supported locale is answered `404`, since the route captured a path that is not a localized address: `/blog/about` matches `/:locale/about` with `locale: "blog"`.

The plug goes in the router's pipeline, after `PutLocale`, whose settings it shares: `PutLocale` keeps its options, with its supported locales resolved for the request, in `conn.private`, so the supported locales, the default and the parameter name are given once. The `404` is raised as `Localize.Plug.LocalePrefix.NotFoundError`, with `plug_status: 404`, so Phoenix renders the application's not-found page. Only `GET` and `HEAD` are redirected; a browser follows a redirect of any other method with a `GET`.

### `Localize.Routes.locale_prefix/2` — for an ordinary router

A router macro that declares the routes in its block twice, plainly and in a `scope "/:locale"`, inside the same live session, so a navigation between languages stays live:

```elixir
live_session :default, on_mount: [Localize.Live.LocalePrefix] do
  locale_prefix do
    live "/about", AboutLive
    live "/products/:id", ProductLive
  end
end
```

`/about`, `/fr/about` and `/de/about` are then real routes, which LiveView can connect to, patch and navigate between, and `~p"/about"` and `~p"/#{locale}/about"` are verified. The locale is a parameter, so a language added at runtime needs no route.

Phoenix matches a path once, so a route whose first segment is dynamic in the block, such as `/:category/:slug`, overlaps its prefixed copy: `/fr/shoes` is either a category or a locale, whichever is declared first. The macro raises at compile time for such a route, and the guide shows the alternatives: a literal first segment, or `Localize.Routes`' per-locale routes.

```elixir
# A CMS: languages and mode per site, paths resolved by the application.
plug Localize.Plug.PutLocale,
  from: [:path_prefix, :session, :accept_language],
  supported: {MyApp.Sites, :locales}

plug Localize.Plug.LocalePrefix,
  mode: {MyApp.Sites, :url_mode},
  default: {MyApp.Sites, :default_locale},
  exists?: {MyApp.Pages, :published?}
```

A CMS with one catch-all route needs no macro: `/*path` already matches `/fr/about`, so LiveView finds a route for every address, and the application resolves the path it is given.

### `Localize.Live.LocalePrefix` — on a live navigation

An `on_mount` hook that attaches a `handle_params` hook. On each navigation it reads the locale parameter from the route the path matches (`Phoenix.Router.route_info/4`, since the params a hook receives include the query string's) and raises `NotFoundError` for one naming no supported locale, which ends a connected LiveView so the browser loads the address and the plug answers `404`. It then calls `target/3` and puts the locale for Localize and Gettext, or pushes a redirect as a `push_navigate`. It is defined only when Phoenix LiveView is loaded.

The hook takes the plug's settings rather than options of its own: `Localize.Live.LocalePrefix.session/1`, given as the live session's `:session`, signs the locale `PutLocale` set and the settings `LocalePrefix` resolved into the page, without writing the session cookie, as `Localize.Plug.live_session_locale/1` does for the locale. A site whose settings are functions of the request resolves them once, at the page's HTTP request. The hook's own options are only `:gettext` and `:session_key`. It puts the settings in the socket's private `:localize_locale_prefix`, where `localized_path/3` reads them.

### Functions of the request

The options of `Localize.Plug.LocalePrefix` that may be functions are called with a `Localize.Routes.Request`, holding the host, the path, the session and the assigns, built from the `conn`. The hook calls `:exists?` with one built from the navigation's URI, the session and the socket's assigns, so a function that finds a site from the host, or from an assign, finds it the same way in both. `PutLocale`'s existing `conn` functions are left as they are.

## Spike: stripping the prefix

Tried on 2026-11-25 with Phoenix LiveView 1.2.15, in `plans/spikes/strip_live_spike_test.exs` (kept as a record, not part of the suite; copy it into `test/` to run it).

LiveView resolves every address it is given, on connect, on `push_patch` and on a navigation, with `Phoenix.LiveView.Route.live_link_info_without_checks/3`, which removes the endpoint's static `script_name` and asks the router for the rest. Nothing lets an application change the path per request, so a prefix removed by a plug before the router is never removed there.

With the prefix removed before a router that has only `/about` and `/other`:

* A request for `/fr/about` renders, with status 200.

* The LiveView's connect is refused: `live/2` returns `{:error, {:redirect, %{to: "http://www.example.com/fr/about"}}}`, the same address, so a browser would render the page, fail to connect and reload it again.

* `push_patch` to `/fr/about` raises `ArgumentError` ("cannot invoke handle_params nor navigate/patch … because it isn't defined in the router") and the LiveView exits.

* `push_navigate` to `/fr/other` becomes a full page load, which then fails to connect.

With each route declared plainly and under `scope "/:locale"`, in one live session:

* `/fr/about` and `/about` connect, with `locale` `"fr"` and the default.

* `push_patch` to `/fr/about?page=2` stays in the LiveView, and `push_navigate` to `/de/other` or back to `/about` is a live navigation.

* `~p"/about"` and `~p"/#{locale}/about"` compile without warnings; `~p"/nowhere"` still warns.

* `/blog/about` matches the prefixed route with `locale: "blog"`, so the parameter must be checked.

Removing the prefix would need LiveView to accept a per-request path rewrite, which is a change for Phoenix LiveView, not for this library. The plan declares the prefix in the router instead.

## Open questions

* **Does a `302` also carry `cache-control: private`?** `vary` already keeps a shared cache from serving one visitor's redirect to another, but some caches ignore it. Recommended: `vary` by default and a `:cache_control` option.

* **Is a `~P` sigil worth adding over `localized_path/3`?** A sigil reads well in templates but adds to Routex's and `Localize.VerifiedRoutes`'s `~q`. The function has landed; a sigil waits for demand.

## Testing

* **A matrix of the rules:** both modes × the default prefix, another prefix, no prefix and a first segment that is not a locale × a remembered locale, an `accept-language` header and neither × `:exists?` absent, true and false × a query string.

* **An ordinary router with `locale_prefix`:** one block answers `/about` and `/fr/about`, a LiveView connects, patches and navigates between languages, `~p` paths stay verified, an unsupported `:locale` is a `404`, and a dynamic first segment is refused at compile time.

* **Parity between the plug and the hook:** the same inputs through `Localize.Plug.LocalePrefix` and `Localize.Live.LocalePrefix` give the same decision, in a live session that navigates between languages, with `locale_prefix` and with a catch-all route.

* **Functions of the request:** a `:supported` function that reads the host or an assign gives the same list from a `conn` and from a socket.

* **Caching:** a `301` carries no `vary` beyond the address's, and a `302` carries the `vary` of the sources consulted.

## Tasks

### Done

* [x] **A guide** — `guides/runtime-locale-routing.md`: translated routes against runtime prefixes, the URL modes, an ordinary router with `locale_prefix`, a CMS with a catch-all route, live navigation, addresses, switchers and caching; its `iex>` examples run as doctests in `test/guides_test.exs`. It led to `Localize.Live.LocalePrefix.get_settings/1`, which a catch-all LiveView needs to split its path. 2026-11-25.

* [x] **`Localize.Live.LocalePrefix`** — the `on_mount` and `handle_params` hook with `session/1`, `Localize.Routes.Request` for the plug's and the hook's functions, and the parity test through a router, an endpoint and a LiveView in both modes. 2026-11-25.

* [x] **`Localize.Routes.Prefix`** — `split/2`, `path/3`, `target/3` and `localized_path/3`, with `:path_prefix` moved onto `split/2`. `localized_path/3` reads the settings `Localize.Plug.LocalePrefix` resolved (a conn), the live hook's (a socket's `:localize_locale_prefix` private key) or a map, keeps a script name in front of the prefix, and logs and returns the path when it cannot localize it. 2026-11-25.

* [x] **`Localize.Plug.LocalePrefix`** — both modes, a `404` (a `NotFoundError` with `plug_status: 404`) for an unsupported locale parameter, `:exists?`, the query string and the script name kept, redirects for `GET` and `HEAD` only; `PutLocale` keeps its settings in `conn.private` for it, and its `vary` serves the `302`. 2026-11-25.

* [x] **`Localize.Routes.locale_prefix/2`** — declares a block plainly and under `/:param`; refuses a dynamic first segment, `forward`, `live_session` and nested blocks at compile time. A later route a prefixed copy matches first is warned of at compile time. Verified routes accept any one-segment path once `/` is in the block, which is documented. 2026-11-25.

* [x] **Try stripping the prefix with LiveView** — it does not work: LiveView refuses to connect to a stripped address and `push_patch` raises; declaring the routes under `/:locale` works. 2026-11-25.
