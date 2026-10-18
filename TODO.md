# TODO

Work planned for `localize_web`. Design documents, when a task needs one, live under `plans/`; shipped changes are described in the [CHANGELOG](CHANGELOG.md).

## Blocked

* [ ] **Drop the type checks in front of Localize calls that raise on the wrong type** — `Localize.HTML.Options.code/3` passes only atoms and strings to `Localize.Currency.validate_currency/1` and `Localize.validate_territory/1`, and `Localize.HTML.Message` passes only map or keyword bindings to `Localize.Message.format_to_safe_list/3`; each raises on other terms in Localize 1.3.0. Blocked on `localize ~> 1.4`, which carries the fixes; then require it and remove the checks.

## Done

* [x] **Live navigation keeps the locale of the route** — `Localize.Routes.localize_live_session/3` puts each locale's live routes in their own live session, and a localized `live` route outside it warns at compile time. 2026-09-27, v1.2.0.

* [x] **URL locale wins by default** — `Localize.Plug.PutLocale` now checks `[:route, :path, :query, :session, :accept_language]` by default. 2026-09-27, v1.2.0.
