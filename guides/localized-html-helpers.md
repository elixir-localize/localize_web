# Localized HTML Helpers

This guide covers the HTML form helpers provided by `localize_web` for generating `<select>` tags and option lists with localized display names.

## Overview

The HTML helpers generate `<select>` tags for currencies, territories, locales, units of measure, and months. Display names are localized according to the current or specified locale using CLDR data from the [Localize](https://hex.pm/packages/localize) library.

Each helper module provides two public functions:

* `select/3` — generates a complete `<select>` tag for use with Phoenix forms.

* `*_options/1` — returns a list of `{display_name, value}` tuples for use with `Phoenix.HTML.Form.options_for_select/2` or custom `<datalist>` elements.

All helpers are also available through the `Localize.HTML` facade module with prefixed names (e.g., `Localize.HTML.territory_select/3`).

## Territory Select

Displays territories with their Unicode flag emoji and localized name:

```elixir
iex> Localize.HTML.Territory.select(:my_form, :territory, selected: :AU)
```

### Options

* `:territories` — a list of territory codes to include. The default is all known territories from `Localize.Territory.territory_codes/0`.

* `:style` — the format of the territory name. Options are `:standard` (default), `:short`, and `:variant`.

* `:locale` — the locale used to localize territory names. The default is `Localize.get_locale/0`.

* `:selected` — the territory code to pre-select. The default is `nil`.

* `:prompt` — a prompt string displayed at the top of the select box.

* `:collator` — a function to sort territories. The default sorts alphabetically by name. Receives a list of `%{territory_code: atom, name: string, flag: string}` maps and returns the sorted list.

* `:mapper` — a function to produce the display text for each territory. The default is `&({&1.flag <> " " <> &1.name, &1.territory_code})`.

### Restricting the Territory List

```elixir
iex> Localize.HTML.Territory.select(:my_form, :territory,
...>   territories: [:US, :GB, :AU, :CA, :NZ],
...>   selected: :AU
...> )
```

### Changing the Display Style

```elixir
# Short names (e.g., "US" instead of "United States")
iex> Localize.HTML.Territory.select(:my_form, :territory, style: :short)
```

### Displaying in a Different Locale

```elixir
# Territory names in French
iex> Localize.HTML.Territory.select(:my_form, :territory, locale: "fr")
```

### Getting Options Without the Select Tag

```elixir
iex> Localize.HTML.Territory.territory_options(
...>   territories: [:US, :GB, :AU],
...>   locale: "fr"
...> )
[{"🇦🇺 Australie", :AU}, {"🇬🇧 Royaume-Uni", :GB}, {"🇺🇸 États-Unis", :US}]
```

## Currency Select

Displays currencies with their code and localized name:

```elixir
iex> Localize.HTML.Currency.select(:my_form, :currency, selected: :USD)
```

### Options

* `:currencies` — a list of currency codes to include. The default is all known currencies from `Localize.Currency.known_currency_codes/0`.

* `:locale` — the locale used to localize currency names. The default is `Localize.get_locale/0`.

* `:selected` — the currency code to pre-select. The default is `nil`.

* `:prompt` — a prompt string displayed at the top of the select box.

* `:collator` — a function to sort currencies. The default sorts alphabetically by name.

* `:mapper` — a function to produce the display text for each currency. The default is `&({&1.code <> " - " <> &1.name, &1.code})`.

### Restricting the Currency List

```elixir
iex> Localize.HTML.Currency.select(:my_form, :currency,
...>   currencies: [:USD, :EUR, :GBP, :JPY],
...>   selected: :USD
...> )
```

### Getting Options Without the Select Tag

```elixir
iex> Localize.HTML.Currency.currency_options(
...>   currencies: [:USD, :EUR, :GBP],
...>   locale: "de"
...> )
```

## Locale Select

Displays locales with their localized display name:

```elixir
iex> Localize.HTML.Locale.select(:my_form, :locale, selected: "en")
```

### Options

* `:locales` — a list of locale identifiers to include. The default is `Localize.all_locale_ids/0` with meta locales excluded.

* `:locale` — the locale used to localize display names. The default is `Localize.get_locale/0`. The special value `:identity` renders each locale's name in its own language.

* `:selected` — the locale identifier to pre-select. The default is `nil`.

* `:prompt` — a prompt string displayed at the top of the select box.

* `:collator` — a function to sort locales. The default sorts alphabetically by display name.

* `:mapper` — a function to produce the display text for each locale. Receives a map with `:display_name`, `:locale`, and `:language_tag` keys. The default is `&{&1.display_name, &1.locale}`.

### Identity Mode

The `:identity` locale renders each option in its own language. This is useful for language-picker UIs where users should see their own language name regardless of the current page locale:

```elixir
iex> Localize.HTML.Locale.select(:my_form, :locale,
...>   locale: :identity,
...>   locales: [:en, :fr, :de, :ja],
...>   selected: "en"
...> )
```

This renders "English", "Français", "Deutsch", and "日本語" each in their respective language. Each `<option>` also receives a `lang` attribute set to its locale for proper browser rendering of non-Latin scripts.

### Restricting the Locale List

```elixir
iex> Localize.HTML.Locale.select(:my_form, :locale,
...>   locales: [:en, :fr, :de, :es, :pt],
...>   selected: "en"
...> )
```

### Getting Options Without the Select Tag

```elixir
iex> Localize.HTML.Locale.locale_options(
...>   locales: [:en, :fr, :de],
...>   locale: :identity
...> )
```

## Unit Select

Displays units of measure with their localized name:

```elixir
iex> Localize.HTML.Unit.select(:my_form, :unit, selected: :kilogram)
```

### Options

* `:units` — a list of unit identifiers to include. The default is all known units grouped by category.

* `:style` — the style of unit name to display. Options are `:long` (default), `:short`, and `:narrow`.

* `:locale` — the locale used to localize unit names. The default is `Localize.get_locale/0`.

* `:selected` — the unit to pre-select. The default is `nil`.

* `:prompt` — a prompt string displayed at the top of the select box.

* `:collator` — a function to sort units. The default sorts alphabetically by display name.

* `:mapper` — a function to produce the display text for each unit. Receives a `{display_name, unit_code}` tuple. The default is the identity function.

### Different Display Styles

```elixir
# Long: "Kilograms"
iex> Localize.HTML.Unit.select(:my_form, :unit, style: :long, selected: :kilogram)

# Short: "kg"
iex> Localize.HTML.Unit.select(:my_form, :unit, style: :short, selected: :kilogram)

# Narrow: "kg"
iex> Localize.HTML.Unit.select(:my_form, :unit, style: :narrow, selected: :kilogram)
```

### Getting Options Without the Select Tag

```elixir
iex> Localize.HTML.Unit.unit_options(style: :short, locale: "fr")
```

## Month Select

Displays month names from CLDR calendar data:

```elixir
iex> Localize.HTML.Month.select(:my_form, :month, selected: 1)
```

### Options

* `:months` — a list of month numbers to include. The default is `1..12`.

* `:style` — the format of the month name. Options are `:wide` (default), `:abbreviated`, and `:narrow`.

* `:calendar` — the calendar from which month names are derived. The default is `Calendar.ISO`.

* `:year` — the year from which the number of months is derived. The default is the current year.

* `:locale` — the locale used to localize month names. The default is `Localize.get_locale/0`.

* `:selected` — the month number to pre-select. The default is `nil`.

* `:prompt` — a prompt string displayed at the top of the select box.

* `:collator` — a function to sort months. The default preserves month order.

* `:mapper` — a function to produce the display text for each month. Receives a `{month_name, month_number}` tuple. The default is the identity function.

### Different Display Styles

```elixir
# Wide: "January", "February", ...
iex> Localize.HTML.Month.select(:my_form, :month, style: :wide)

# Abbreviated: "Jan", "Feb", ...
iex> Localize.HTML.Month.select(:my_form, :month, style: :abbreviated)

# Narrow: "J", "F", ...
iex> Localize.HTML.Month.select(:my_form, :month, style: :narrow)
```

### Getting Options Without the Select Tag

```elixir
iex> Localize.HTML.Month.month_options(style: :abbreviated, locale: "de")
```

## Customizing Display with Mapper and Collator

All select helpers accept `:mapper` and `:collator` options for full control over display text and sort order.

### Custom Mapper

The mapper function transforms each item into a `{display_text, value}` tuple for the select options:

```elixir
# Territory: show only the name without the flag
iex> Localize.HTML.Territory.select(:my_form, :territory,
...>   mapper: fn territory ->
...>     {territory.name, territory.territory_code}
...>   end
...> )
```

### Custom Collator

The collator function receives the full list of items and returns them in the desired order:

```elixir
# Territory: sort by territory code instead of name
iex> Localize.HTML.Territory.select(:my_form, :territory,
...>   collator: fn territories ->
...>     Enum.sort_by(territories, & &1.territory_code)
...>   end
...> )
```

### Combining Mapper and Collator

```elixir
# Currency: show symbol + name, sorted by code
iex> Localize.HTML.Currency.select(:my_form, :currency,
...>   currencies: [:USD, :EUR, :GBP],
...>   mapper: fn currency ->
...>     {"#{currency.code} - #{currency.name}", currency.code}
...>   end,
...>   collator: fn currencies ->
...>     Enum.sort_by(currencies, & &1.code)
...>   end
...> )
```

## Using with Phoenix Forms

The select helpers work with both Phoenix form structs and atom-based form names:

```elixir
# With an atom form name
Localize.HTML.Territory.select(:my_form, :territory, selected: :AU)

# With a Phoenix.HTML.Form struct in a template
<.form let={f} for={@changeset} action={@action}>
  <%= Localize.HTML.Territory.select(f, :territory, selected: :AU) %>
</.form>
```

## Using the Facade Module

The `Localize.HTML` facade module provides all helpers with prefixed names:

```elixir
Localize.HTML.territory_select(form, field, options)
Localize.HTML.territory_options(options)
Localize.HTML.currency_select(form, field, options)
Localize.HTML.currency_options(options)
Localize.HTML.locale_select(form, field, options)
Localize.HTML.locale_options(options)
Localize.HTML.unit_select(form, field, options)
Localize.HTML.unit_options(options)
```
