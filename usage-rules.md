# Localize Web usage rules

Rules for LLM coding agents using `localize_web` as a dependency. Not exhaustive — see the HexDocs guides for full reference.

## What this package is for

Connecting [`localize`](https://hex.pm/packages/localize) to Phoenix: resolving the locale from an incoming request, localized routes, and HTML helpers.

## Core conventions

* Resolve the locale in a plug, once, at the start of the request, and let everything downstream read `Localize.get_locale/0`. Do not thread a locale through function arguments.

* `Localize.AcceptLanguage.parse/1` and `best_match/1` implement the header properly, including quality values and fallback. Use them rather than reading the header by hand.

## Module map

| Task | Use |
|---|---|
| Parse the `accept-language` header | `Localize.AcceptLanguage.parse/1`, `tokenize/1` |
| Choose the best supported locale | `Localize.AcceptLanguage.best_match/1` |
| Set the locale for a request | `Localize.Plug.*`, `put_locale_from_session/2` |
| Localized route paths | `Localize.Routes` |
| Territory `<select>` and options | `Localize.HTML.Territory.select/3`, `territory_options/1` |

## Things not to do

* **Do not choose the content language from the visitor's IP geolocation.** Location is not language, and it fails for travellers, expatriates, multilingual territories and VPN users. `accept-language` is the user's explicit statement of preference; honour it. Geolocation is at best a tiebreaker when the header offers nothing supported.

* When you do vary on the header, send `Vary: Accept-Language` so caches and CDNs do not serve one visitor's language to another. `Localize.Plug.PutLocale` sends `vary` for the request headers it reads, unless `vary: false` is set; `Localize.Plug.AcceptLanguage` sends none.

* Do not parse `accept-language` with `String.split(",")`. It carries quality values, ranges and ordering rules.

* Do not persist a locale in the session without also offering a way to change it, and do not let a stale session locale override a fresh explicit choice. `Localize.Plug.PutSession` with `from: [:route, :path, :query, :body]` stores a locale the visitor chose and not one inferred from the browser; give a `live_session` that is not localized `session: {Localize.Plug, :live_session_locale, []}` so a connected LiveView still gets the locale. Send `cache-control: private` on a response for which `Localize.Plug.PutSession.stored?/1` is true.

* Do not fall back to a hard-coded `:en` without trying the locale's parent chain first — Localize resolves `:"de-AT"` to `:de` before it gives up.
