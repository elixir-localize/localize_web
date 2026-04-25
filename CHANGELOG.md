# Changelog

All notable changes to this project will be documented in this file. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] - 2026-04-25

### Bug Fixes

* Ignore out-of-range and zero-weight q-values when parsing `accept-language` headers per RFC 9110. Thanks to @rubas for the PR. Closes #6.

* Expose `month_select/3` and `month_options/1` on the `Localize.HTML` facade as documented in the moduledoc. Thanks to @rubas for the PR. Closes #9.

* Honor the `:calendar` option in `Localize.HTML.Month` by sourcing month labels from the CLDR calendar returned by the calendar module's `cldr_calendar_type/0` function. Thanks to @rubas for the PR. Closes #10.

### Changes

* Document that `fetch_session/1` must run before `Localize.Plug.PutLocale` when `:session` or `:cookie` sources are used. Thanks to @rubas for the PR. Closes #7.

## [0.5.0] - 2026-04-17

### Bug Fixes

* Be more lenient when parsing invalid `accept-language` headers. Duplicate `q=` might be invalid syntax but they shouldn't crash the parser. Thanks to @woylie for the report. Closes #3.

## [0.4.0] - 2026-04-16

### Changes

* Don't call `Localize.default_locale/0` at compile time. That causes `localize` to be loaded at compile time which causes issues on machines with constrained resources. Defer the call to runtime.

## [0.3.0] - 2026-04-16

### Changes

* Make `phoenix_html_helpers` a required dependency (it was optional).

## [0.2.0] - 2026-04-15

### Changes

* Fix docs links in the package.

## [0.1.0] - 2026-04-13

### Highlights

Initial release of `localize_web`, providing Phoenix integration for the [Localize](https://hex.pm/packages/localize) library. This library consolidates the functionality previously provided by `ex_cldr_plugs`, `ex_cldr_routes`, and `cldr_html` into a single package.

* **Locale discovery plugs** that detect the user's locale from the accept-language header, query parameters, URL path, session, cookies, hostname TLD, or custom functions. Includes session persistence and LiveView support.

* **Compile-time route localization** that translates route path segments using Gettext, generating localized routes for each configured locale. Supports locale interpolation, nested resources, and all standard Phoenix route macros.

* **Verified localized routes** via the `~q` sigil, providing compile-time verification of localized paths that dispatch to the correct translation based on the current locale.

* **Localized HTML form helpers** that generate `<select>` tags and option lists for currencies, territories, locales, units of measure, and months with localized display names.

See the [README](README.md) for full documentation and usage examples.
