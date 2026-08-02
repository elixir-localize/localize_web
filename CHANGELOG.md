# Changelog

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] — 2026-08-03

### Fixed

* `~q` now resolves the `#{locale}`, `#{language}` and `#{territory}` interpolation forms, which previously raised `a dynamic ~p interpolation must follow a static segment` at compile time in every position. Substituting the token left the enclosing `::binary` wrapper in place, so Phoenix saw a literal inside a dynamic segment and matched none of its route-verification clauses. Thanks to @sumerokr for the report. Closes #15.

* `mix phx.routes <Router>.LocalizedRoutes` now works, where it raised `function ... formatted_routes/1 is undefined`. The generated module hosts route definitions but is not a router, so the `formatted_routes/1` and `__helpers__/0` callbacks `Phoenix.Router.ConsoleFormatter` calls are now defined on it. Thanks to @sumerokr for the report. Closes #16.

### Documentation

* Align the documentation module names to the canonical Phoenix generator forms. Thanks to @sumerokr for the PRs. Closes #13, #14.

* `Localize.VerifiedRoutes` documents that every option other than `:gettext` passes through to `Phoenix.VerifiedRoutes`, and that `:statics` in particular must be kept when converting from `use Phoenix.VerifiedRoutes` — without it the asset paths in the default Phoenix layouts warn that no route matches ([#16](https://github.com/elixir-localize/localize_web/issues/16)).

* The guides now name web-layer modules `MyAppWeb.*` as Phoenix's generators do, rather than `MyApp.*`, and the installation snippets require `~> 1.0` instead of the long-superseded `~> 0.1.0`. Thanks to @sumerokr for both ([#13](https://github.com/elixir-localize/localize_web/pull/13), [#14](https://github.com/elixir-localize/localize_web/pull/14)), and for the two reports above.

* The `LocalizeWeb` module. It defined no functions — only a moduledoc listing the plugs, routes and HTML helpers, all of which live under `Localize.*` and are unaffected.

## [1.0.0] — 2026-07-31

The first stable release, built on Localize 1.0.

### Changes

* Requires `localize ~> 1.0`.

### Fixed

* `Localize.HTML.Unit.select/3` is specified as returning `{:error, Exception.t()}`. Localize 1.0 reports an invalid unit or locale as an exception struct rather than a `{module, message}` tuple, so the previous specification did not describe what the function returns.

* `currency_options/1`, `locale_options/1`, `territory_options/1` and `unit_options/1` no longer claim to return an error tuple. They validate by raising, so the documented error return could not occur.

## [0.8.0] — 2026-06-25

### Bug Fixes

* `Localize.Plug.PutSession` no longer rewrites the session (and emits a redundant `Set-Cookie`) when the stored locale is unchanged, avoiding needless response bandwidth and preventing caching layers from treating responses as private. Ported from `ex_cldr_plugs` with thanks @maltoe.

## [0.7.0] — 2026-05-13

### Enhancements

* `Localize.HTML.Message` — new function component (and `Localize.HTML.message/1` facade) that renders an MF2 message preserving inline markup. The `link` default renderer uses Phoenix's `<.link>` and so accepts `href`, `navigate`, or `patch` MF2 attributes; per-call `:components` and `config :localize_web, :mf2_markup, components: %{…}` override the defaults, and unknown tags raise `Localize.HTML.Message.UnknownMarkupError`.

* `Localize.HTML.t/1` and `t/2` — new compile-time macros for HEEx templates that combine Gettext extraction, MF2 binding interpolation, and markup rendering in one call: `{t("Read {#bold}terms{/bold}")}`. Elixir `#{@user.name}` interpolations have the `assigns` prefix stripped so derived binding names match what a developer would write (`@user.name` → `user_name`).

### Test infrastructure

* `mix test` now runs `mix localize.download_locales` first, populating CLDR data for the locales referenced by the suite (`en`, `fr`, `de`, `th`, `ja`, `ar`, `zh`, `zh-Hans`, `zh-Hant`). Fresh checkouts and CI no longer fail on missing locale display data.

## [0.6.0] — 2026-05-11

### Enhancements

* Add `path_for/2` and `url_for/2` macros to `Localize.VerifiedRoutes` to render a verified path or URL in an explicit locale without changing the process-wide locale, supporting language-switcher and hreflang use cases that need every configured locale rendered in one template pass.

## [0.5.1] — 2026-04-25

### Bug Fixes

* Ignore out-of-range and zero-weight q-values when parsing `accept-language` headers per RFC 9110. Thanks to @rubas for the PR. Closes #6.

* Expose `month_select/3` and `month_options/1` on the `Localize.HTML` facade as documented in the moduledoc. Thanks to @rubas for the PR. Closes #9.

* Honor the `:calendar` option in `Localize.HTML.Month` by sourcing month labels from the CLDR calendar returned by the calendar module's `cldr_calendar_type/0` function. Thanks to @rubas for the PR. Closes #10.

### Changes

* Document that `fetch_session/1` must run before `Localize.Plug.PutLocale` when `:session` or `:cookie` sources are used. Thanks to @rubas for the PR. Closes #7.

## [0.5.0] — 2026-04-17

### Bug Fixes

* Be more lenient when parsing invalid `accept-language` headers. Duplicate `q=` might be invalid syntax but they shouldn't crash the parser. Thanks to @woylie for the report. Closes #3.

## [0.4.0] — 2026-04-16

### Changes

* Don't call `Localize.default_locale/0` at compile time. That causes `localize` to be loaded at compile time which causes issues on machines with constrained resources. Defer the call to runtime.

## [0.3.0] — 2026-04-16

### Changes

* Make `phoenix_html_helpers` a required dependency (it was optional).

## [0.2.0] — 2026-04-15

### Changes

* Fix docs links in the package.

## [0.1.0] — 2026-04-13

### Highlights

Initial release of `localize_web`, providing Phoenix integration for the [Localize](https://hex.pm/packages/localize) library. This library consolidates the functionality previously provided by `ex_cldr_plugs`, `ex_cldr_routes`, and `cldr_html` into a single package.

* **Locale discovery plugs** that detect the user's locale from the accept-language header, query parameters, URL path, session, cookies, hostname TLD, or custom functions. Includes session persistence and LiveView support.

* **Compile-time route localization** that translates route path segments using Gettext, generating localized routes for each configured locale. Supports locale interpolation, nested resources, and all standard Phoenix route macros.

* **Verified localized routes** via the `~q` sigil, providing compile-time verification of localized paths that dispatch to the correct translation based on the current locale.

* **Localized HTML form helpers** that generate `<select>` tags and option lists for currencies, territories, locales, units of measure, and months with localized display names.

See the [README](README.md) for full documentation and usage examples.
