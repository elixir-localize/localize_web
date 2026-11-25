# TODO

Work planned for `localize_web`. Design documents, when a task needs one, live under `plans/`; shipped changes are described in the [CHANGELOG](CHANGELOG.md).

## Open

* [ ] **Warn when two Gettext locales collapse into one locale id** — `de` and `de_CH` both resolve to `de-CH` when only `de-CH` is supported, so they share one route tag and the routes and helpers can translate with different Gettext locales. `Localize.Routes.locales_from_gettext/1` should warn at compile time when a backend's locales collapse. Raised in #27.

## Deferred

* [ ] **Store only a chosen locale by default** — `Localize.Plug.PutSession` stores a locale from any source unless given `:from`, so an application gets the first-visit cookie until it opts out. Parked for 2.0: the new default breaks a LiveView in a live session that has not been given `Localize.Plug.live_session_locale/1`.

## Done

* [x] **A `content-language` response header** — `PutLocale` takes `content_language: true`, which names the canonical tag of the locale it set; off by default. 2026-11-25, unreleased (1.5.0).

* [x] **A language switcher** — `Localize.HTML.LanguageSwitcher.links/2` and `language_switcher/1` from the hreflang map: names in their own language cased for a menu (`capitalization: :ui_list_or_menu`, localize 1.10), `lang`/`dir`, `aria-current`, current matched as the plugs match, collated in the current locale. 2026-11-25, unreleased (1.5.0).

* [x] **`lang` and `dir` for the document** — `Localize.HTML.Document.attributes/1`, `html/1` for the root layout and `live_locale/1`, which sets `<html lang dir>` with `Phoenix.LiveView.JS` when a page in another locale mounts in the same live session. Direction from `Localize.Locale.direction/1`. 2026-11-25, unreleased (1.5.0).

* [x] **Sort names with CLDR collation** — the currency, territory, locale, unit and subdivision helpers sort by `Localize.Collation` in the display locale (`Localize.HTML.Options.collate/3`, options resolved once per list), where four sorted by bytes and subdivisions by root collation. 2026-11-25, unreleased (1.5.0).

* [x] **A configurable session key** — `PutLocale` takes `:session_key`, which `PutSession`, `live_session_locale/1` and `get_session_key/1` follow; `put_locale_from_session/2` and `localize_live_session/3` take it too, so a site's pages and its admin keep two locales (mishka_cms_core's shape). 2026-11-25, unreleased (1.5.0).

* [x] **A language prefix on the path** — `PutLocale` takes a `:path_prefix` source, the first path segment when it names a supported locale exactly, for an optional prefix and catch-all routes (mishka_cms_core's `LanguagePlug` shape). 2026-11-25, unreleased (1.5.0).

* [x] **Supported locales known only at runtime** — `PutLocale` and `Plug.AcceptLanguage` take `:supported` (a list or a function of the request) and `AcceptLanguage.best_match/2` a list; the host source is now matched too. 2026-11-24, unreleased (1.5.0).

* [x] **A locale the application does not support is passed over** — `PutLocale` takes an identifier from the URL, a form, a cookie or the session only when it matches a supported locale, as `accept-language` did, so `?locale=tlh` no longer resolves to `und` nor `?locale=pt` to the first supported locale. Localize is right to answer for both when formatting; the fault was taking its answer as a match. 2026-11-17, v1.4.0.

* [x] **Store only a locale the visitor chose** — `Localize.Plug.PutSession` takes `:from`, `Localize.Plug.PutLocale.get_locale_source/1` says which source decided, and `Localize.Plug.live_session_locale/1` hands a connected LiveView the locale without the cookie. 2026-11-17, v1.4.0.

* [x] **Document `cache-control: private` on a response that writes the session** — in the `vary` section of the HTTP locale discovery guide, with the cost of keying on a raw `accept-language`. 2026-11-17, v1.4.0.

* [x] **`:vary` option on `PutLocale`** — `vary: false` turns the plug's `vary` header off, and the header is added in a line of its own without rewriting existing ones. 2026-11-17, v1.4.0.

* [x] **Drop the type checks in front of Localize calls that raise on the wrong type** — `localize ~> 1.4` is required and `Localize.HTML.Options.code/3` and the bindings check in `Localize.HTML.Message` are gone; Localize 1.4 returns `{:error, exception}` for a value of the wrong type. 2026-10-24, v1.3.0.

* [x] **Live navigation keeps the locale of the route** — `Localize.Routes.localize_live_session/3` puts each locale's live routes in their own live session, and a localized `live` route outside it warns at compile time. 2026-09-27, v1.2.0.

* [x] **URL locale wins by default** — `Localize.Plug.PutLocale` now checks `[:route, :path, :query, :session, :accept_language]` by default. 2026-09-27, v1.2.0.
