defmodule Localize.HTML do
  @moduledoc """
  Facade module providing HTML form select helpers for localized data.

  This module delegates to specialized submodules that generate `<select>` tags and option lists for currencies, territories, locales, units of measure, and months. Each helper localizes display names according to the current or specified locale using the [Localize](https://hex.pm/packages/localize) library.

  ## Delegate Functions

  * `currency_select/3` and `currency_options/1` — see `Localize.HTML.Currency`.

  * `territory_select/3` and `territory_options/1` — see `Localize.HTML.Territory`.

  * `locale_select/3` and `locale_options/1` — see `Localize.HTML.Locale`.

  * `unit_select/3` and `unit_options/1` — see `Localize.HTML.Unit`.

  """

  defdelegate currency_select(form, field, options), to: Localize.HTML.Currency, as: :select
  defdelegate currency_options(options), to: Localize.HTML.Currency, as: :currency_options

  defdelegate unit_select(form, field, options), to: Localize.HTML.Unit, as: :select
  defdelegate unit_options(options), to: Localize.HTML.Unit, as: :unit_options

  defdelegate territory_select(form, field, options), to: Localize.HTML.Territory, as: :select
  defdelegate territory_options(options), to: Localize.HTML.Territory, as: :territory_options

  defdelegate locale_select(form, field, options), to: Localize.HTML.Locale, as: :select
  defdelegate locale_options(options), to: Localize.HTML.Locale, as: :locale_options
end
