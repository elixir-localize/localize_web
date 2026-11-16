# TODO

Work planned for `localize_web`. Design documents, when a task needs one, live under `plans/`; shipped changes are described in the [CHANGELOG](CHANGELOG.md).

## Open

* [ ] **Warn when two Gettext locales collapse into one locale id** — `de` and `de_CH` both resolve to `de-CH` when only `de-CH` is supported, so they share one route tag and the routes and helpers can translate with different Gettext locales. `Localize.Routes.locales_from_gettext/1` should warn at compile time when a backend's locales collapse. Raised in #27.

## Deferred

* [ ] **Store only a chosen locale** — `Localize.Plug.PutSession` stores whatever `PutLocale` resolved, so one visit to a localized URL rewrites the stored preference and a first visit sets a session cookie. Parked until a dedicated language cookie is designed; LiveView mounts outside a localized live session read the locale from the session today.

## Done

* [x] **`:vary` option on `PutLocale`** — `vary: false` turns the plug's `vary` header off, and the header is added in a line of its own without rewriting existing ones. 2026-11-16, v1.4.0.

* [x] **Drop the type checks in front of Localize calls that raise on the wrong type** — `localize ~> 1.4` is required and `Localize.HTML.Options.code/3` and the bindings check in `Localize.HTML.Message` are gone; Localize 1.4 returns `{:error, exception}` for a value of the wrong type. 2026-10-24, v1.3.0.

* [x] **Live navigation keeps the locale of the route** — `Localize.Routes.localize_live_session/3` puts each locale's live routes in their own live session, and a localized `live` route outside it warns at compile time. 2026-09-27, v1.2.0.

* [x] **URL locale wins by default** — `Localize.Plug.PutLocale` now checks `[:route, :path, :query, :session, :accept_language]` by default. 2026-09-27, v1.2.0.
