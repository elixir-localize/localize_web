defmodule Localize.HTML do
  @moduledoc """
  Implements HTML Form selects for localized display of
  [Localize](https://hex.pm/packages/localize)-based data.

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
