# TODO

Work planned for `localize_web`. Design documents, when a task needs one, live under `plans/`; shipped changes are described in the [CHANGELOG](CHANGELOG.md).

## Open

* [ ] **Warn when two Gettext locales collapse into one locale id** — `de` and `de_CH` both resolve to `de-CH` when only `de-CH` is supported, so they share one route tag and the routes and helpers can translate with different Gettext locales. `Localize.Routes.locales_from_gettext/1` should warn at compile time when a backend's locales collapse. Raised in #27.

* [ ] **Document `cache-control: private` on a response that writes the session** — behind `plug_http_cache` a cacheable page that stores a chosen locale is itself stored, and the next visitor to choose is served it without the cookie, so their choice is lost. Sending such a response `private` fixes it (tested in `localize_cache_probe`, `/private-session`); say so in the `vary` section of the HTTP locale discovery guide.

## Deferred

* [ ] **Store only a locale the visitor chose** — `Localize.Plug.PutSession` stores a locale inferred from `accept-language`, so every first visit sets a cookie, and Varnish and nginx then store none of those pages. Tried in `localize_cache_probe` (`/chosen`), where two new visitors share a copy behind every cache at the cost of one copy for each form of `accept-language`; parked until `PutLocale` records which source decided and a connected LiveView can be handed the resolved locale without the cookie session.

## Done

* [x] **`:vary` option on `PutLocale`** — `vary: false` turns the plug's `vary` header off, and the header is added in a line of its own without rewriting existing ones. 2026-11-17, v1.4.0.

* [x] **Drop the type checks in front of Localize calls that raise on the wrong type** — `localize ~> 1.4` is required and `Localize.HTML.Options.code/3` and the bindings check in `Localize.HTML.Message` are gone; Localize 1.4 returns `{:error, exception}` for a value of the wrong type. 2026-10-24, v1.3.0.

* [x] **Live navigation keeps the locale of the route** — `Localize.Routes.localize_live_session/3` puts each locale's live routes in their own live session, and a localized `live` route outside it warns at compile time. 2026-09-27, v1.2.0.

* [x] **URL locale wins by default** — `Localize.Plug.PutLocale` now checks `[:route, :path, :query, :session, :accept_language]` by default. 2026-09-27, v1.2.0.
