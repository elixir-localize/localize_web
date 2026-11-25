# Runtime locale routing

**Status:** draft, 2026-11-25

A design for an optional locale prefix handled at runtime: `/about` in the default language beside `/fr/about`, with redirects between the forms, the same decision on a live navigation, and helpers to build the addresses. It serves two kinds of application: one with an ordinary router that wants every language without a copy of its routes per language, and one whose pages are data, such as a CMS answering every address with one catch-all route and choosing its languages per site. `mishka_cms_core` (`MishkaCmsCore.Runtime.Plugs.LanguagePlug`, at `a86940a`) is the second kind and the source of the requirements. Nothing here is built yet; the target is the release after 1.5.0.

## The problem

`Localize.Routes` localizes routes at compile time. Each route is generated once per Gettext locale with its path segments translated, and `#{locale}` interpolation puts the locale in the path for every language, the default included. There is no form in which the default language is unprefixed, and nothing redirects `/en/about` to `/about`, or an address with no language to the visitor's. An application that wants `/about` and `/fr/about` writes its routes twice and its redirects by hand. One whose addresses are data cannot use compile-time routes at all.

1.5.0 gives both the parts that discover and present a locale: the `:path_prefix` source and a `:supported` function of the request, `accept-language` matched against that list, `:session_key`, `Localize.HTML.Document` for `<html lang dir>` across live navigation, and `Localize.HTML.Hreflang` and `Localize.HTML.LanguageSwitcher` built from a map of locale to URL. What is missing is the routing: deciding whether to answer an address or send the visitor to another form of it, building those addresses, and making the same decision on a live navigation, where no plug runs.

## Compile time, runtime and verified routes

Phoenix's verified routes check a path against the router when the application compiles, which is worth keeping. They need the routes to be known then, and that is where the line between compile-time and runtime routing falls:

* **A translated path segment** (`/produits` for `/products`) changes the path, so it must be a route, made at compile time. `Localize.Routes` does this with Gettext, and so does [Routex](https://hex.pm/packages/routex), which also serves the default locale unprefixed and makes `~p` branch to the current locale's route. This plan does not compete with either.

* **A locale prefix** wraps a path without changing it. Removed before the router, it leaves one set of routes that serves every language, so `~p"/about"` stays verified, and the prefix is added at runtime when an address is built. This is the part that can be done at runtime without giving up verified routes, and it is this plan's subject.

* **A page whose path is data**, a CMS page, has no route to verify. Its application resolves the path itself and needs the prefix rules, the redirects and the address helpers, but not the router integration.

So the plan has a layer that strips the prefix for ordinary routers, a layer of rules and helpers that every application uses, and a hook for live navigation.

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

* **Strip the prefix before the router, on top of shared rules, with a hook for live navigation.** Serves both kinds of application, keeps verified routes, and puts every rule in one place. Chosen.

* **Leave it to applications.** Each writes the rules again, and the places it goes wrong, exact prefix matching, `301` against `302` and `vary`, are the ones a library should settle. Rejected.

## Decision

### `Localize.Routes.Prefix` — the rules and helpers

Functions of a path with no `conn`, used by every layer:

* **`split(path, supported)`** returns `{locale, rest}` when the first segment names a supported locale exactly, and `{nil, path}` otherwise. The `:path_prefix` source uses the same function.

* **`path(path, locale, options)`** returns the address of `path` in `locale` under `:mode` and `:default`, adding, dropping or replacing the prefix: `path("/about", :fr, mode: :prefix_others, default: :en)` is `"/fr/about"`, and `path("/fr/about", :en, ...)` is `"/about"`.

* **`target(path, locale, source, options)`** returns `:serve` or `{:redirect, path, 301 | 302}`, for the locale `Localize.Plug.PutLocale` resolved and the source it came from, under `:mode` and `:default`, with an optional `:exists?` test.

A `~P` sigil or a `localized_path/2` helper composes a verified route with `path/3`, so `~p"/about"` is checked at compile time and given the current locale's prefix at runtime.

### `Localize.Plug.LocalePrefix` — on a request

Runs after `Localize.Plug.PutLocale`, which has resolved the locale from `:path_prefix` and the other sources, and applies the mode:

* Under `:prefix_others`, a locale found by `:path_prefix` that is the default is redirected to the address without the prefix, with a `301`.

* Under `:prefix_all`, a locale found by any other source is redirected to the address with its prefix, with a `302`, or, when `:exists?` is given and does not hold, to the default language's address.

* **`strip: true`**, for an ordinary router, removes the matched segment from `conn.path_info` after the decision, so the router matches `/fr/about` as `/about`. Without it the path is left whole, for an application that resolves its own paths. The plug then goes in the endpoint, before the router, where `strip: true` is needed, or in a pipeline, where only some routes are localized.

```elixir
# An ordinary router: one set of routes for every language.
plug Localize.Plug.PutLocale, from: [:path_prefix, :session, :accept_language]
plug Localize.Plug.LocalePrefix, mode: :prefix_others, strip: true
plug MyAppWeb.Router

# A CMS: languages and mode per site, paths resolved by the application.
plug Localize.Plug.PutLocale,
  from: [:path_prefix, :session, :accept_language],
  supported: {MyApp.Sites, :locales}

plug Localize.Plug.LocalePrefix,
  mode: {MyApp.Sites, :url_mode},
  default: {MyApp.Sites, :default_locale},
  exists?: {MyApp.Pages, :published?}
```

### `Localize.Live.LocalePrefix` — on a live navigation

An `on_mount` hook that attaches a `handle_params` hook. On each navigation it splits the URI with `Localize.Routes.Prefix.split/2`, puts the locale for Localize and Gettext, and calls `target/4`; a redirect becomes a `push_navigate`. It is defined only when Phoenix LiveView is loaded.

### Functions of the request

The options that may be functions are called with the `conn` by the plugs. A live navigation has no `conn`, so the hook calls them with a `Localize.Routes.Request` holding the host, the path, the session and the socket's assigns. A function that finds a site from the host, or from an assign set by the application's own `on_mount`, finds it the same way in both. The request form is accepted by the new plug and hook from the start; `PutLocale`'s existing `conn` functions are left as they are.

## Open questions

* **Does a stripped prefix survive a live navigation?** LiveView matches a `navigate` against the router by the URI's path, which keeps the prefix. With `strip: true`, `/fr/about` has no route of its own. The hook, or a router helper that declares the stripped paths, must make LiveView match `/about` for it. This decides whether `strip: true` works with LiveView, and is the first thing to try.

* **Does a `302` also carry `cache-control: private`?** `vary` already keeps a shared cache from serving one visitor's redirect to another, but some caches ignore it. Recommended: `vary` by default and a `:cache_control` option.

* **Does the hook push a redirect, or hand the decision to the LiveView?** Recommended: push it, with an option to receive the decision instead.

* **Is `~P` worth a sigil, or is `localized_path/2` enough?** A sigil reads well in templates but adds to Routex's and `Localize.VerifiedRoutes`'s `~q`. Recommended: the function first.

## Testing

* **A matrix of the rules:** both modes × the default prefix, another prefix, no prefix and a first segment that is not a locale × a remembered locale, an `accept-language` header and neither × `:exists?` absent, true and false × a query string.

* **An ordinary router with `strip: true`:** one route set answers `/about` and `/fr/about`, `~p` paths stay verified, and `localized_path/2` gives each language's address.

* **Parity between the plug and the hook:** the same inputs through `Localize.Plug.LocalePrefix` and `Localize.Live.LocalePrefix` give the same decision, in a live session that navigates between languages, with and without `strip: true`.

* **Functions of the request:** a `:supported` function that reads the host or an assign gives the same list from a `conn` and from a socket.

* **Caching:** a `301` carries no `vary` beyond the address's, and a `302` carries the `vary` of the sources consulted.

## Tasks

* [ ] **Try `strip: true` with LiveView** — whether a live navigation to a stripped path can be matched, and how; the answer shapes the rest.

* [ ] **`Localize.Routes.Prefix`** — `split/2`, `path/3` and `target/4`, with `:path_prefix` moved onto `split/2`, and `localized_path/2`.

* [ ] **`Localize.Plug.LocalePrefix`** — the two modes, `strip:`, the optional `:exists?`, the query string and the `vary` of a `302`.

* [ ] **`Localize.Live.LocalePrefix`** — the `on_mount` and `handle_params` hook, and `Localize.Routes.Request` for its functions, with the parity test.

* [ ] **A guide** — runtime locale routing beside `Localize.Routes`: when each fits, an ordinary router with `strip: true`, and a CMS with sites, modes, alternates and a switcher built with `Localize.Routes.Prefix.path/3`.
