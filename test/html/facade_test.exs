defmodule Localize.HTML.FacadeTest do
  use ExUnit.Case, async: true

  import Phoenix.HTML, only: [safe_to_string: 1]

  setup do
    Localize.put_locale(:en)
    :ok
  end

  @delegates [
    {:currency, Localize.HTML.Currency, :currency_options, [currencies: [:USD, :EUR]]},
    {:unit, Localize.HTML.Unit, :unit_options, [units: [:meter, :liter]]},
    {:territory, Localize.HTML.Territory, :territory_options, [territories: [:US, :FR]]},
    {:subdivision, Localize.HTML.Subdivision, :subdivision_options, [territory: :au]},
    {:locale, Localize.HTML.Locale, :locale_options, [locales: [:en, :fr]]},
    {:month, Localize.HTML.Month, :month_options, [months: [1, 2]]}
  ]

  for {name, module, options_fun, options} <- @delegates do
    test "Localize.HTML.#{name}_select/3 and #{options_fun}/1 delegate to #{inspect(module)}" do
      options = unquote(options)

      assert apply(Localize.HTML, unquote(options_fun), [options]) ==
               apply(unquote(module), unquote(options_fun), [options])

      assert safe_to_string(
               apply(Localize.HTML, :"#{unquote(name)}_select", [:form, :field, options])
             ) ==
               safe_to_string(unquote(module).select(:form, :field, options))
    end
  end

  test "each helper works with no options" do
    for module <- [
          Localize.HTML.Currency,
          Localize.HTML.Unit,
          Localize.HTML.Month,
          Localize.HTML.Territory
        ] do
      assert safe_to_string(module.select(:form, :field)) =~ "<select"
    end

    assert [_ | _] = Localize.HTML.Currency.currency_options()
    assert [_ | _] = Localize.HTML.Unit.unit_options()
    assert [_ | _] = Localize.HTML.Month.month_options()

    assert {:error, %Localize.InvalidValueError{}} =
             Localize.HTML.Subdivision.subdivision_options()

    assert {:error, %Localize.InvalidValueError{}} =
             Localize.HTML.Subdivision.select(:form, :field)
  end

  test "Month renders each style" do
    assert [{"January", 1}] = Localize.HTML.Month.month_options(months: [1], style: :wide)
    assert [{"Jan", 1}] = Localize.HTML.Month.month_options(months: [1], style: :abbreviated)
    assert [{"J", 1}] = Localize.HTML.Month.month_options(months: [1], style: :narrow)
  end

  test "Month labels a month the calendar does not name with its number" do
    assert [{"Month 13", 13}] = Localize.HTML.Month.month_options(months: [13])
  end
end
