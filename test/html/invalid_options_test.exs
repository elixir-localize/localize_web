defmodule Localize.HTML.InvalidOptionsTest do
  # The select helpers run on the render path, so every invalid option
  # must come back as `{:error, exception}` rather than raising.
  use ExUnit.Case, async: true

  @garbage ["!!!", "", :"", %{}, 42, {:a}, [%{}], String.duplicate("x", 3000)]

  @helpers [
    {Localize.HTML.Currency, :currency_options, :currencies, []},
    {Localize.HTML.Locale, :locale_options, :locales, [locales: [:en, :fr]]},
    {Localize.HTML.Territory, :territory_options, :territories, []},
    {Localize.HTML.Unit, :unit_options, :units, []},
    {Localize.HTML.Subdivision, :subdivision_options, :territory, [territory: :us]},
    {Localize.HTML.Month, :month_options, :months, []}
  ]

  defp assert_error(result, label) do
    assert {:error, %{__exception__: true}} = result, "expected an error for #{label}"
  end

  for {module, options_fun, list_key, base} <- @helpers do
    describe "#{inspect(module)}" do
      test "returns an error for invalid :locale, :selected and :#{list_key}" do
        for key <- [:locale, :selected, unquote(list_key)],
            value <- @garbage,
            # Subdivision passes any atom or string :selected through, as
            # either form of a subdivision code is accepted.
            not (unquote(module) == Localize.HTML.Subdivision and key == :selected and
                   (is_atom(value) or is_binary(value))) do
          options = Keyword.put(unquote(base), key, value)
          label = "#{inspect(unquote(module))} #{key}: #{String.slice(inspect(value), 0, 20)}"

          assert_error(apply(unquote(module), unquote(options_fun), [options]), label)
          assert_error(unquote(module).select(:form, :field, options), label)
        end
      end

      test "returns an error for invalid :collator and :mapper" do
        for key <- [:collator, :mapper], value <- [nil, "x", &Function.identity/2] do
          options = Keyword.put(unquote(base), key, value)
          assert_error(apply(unquote(module), unquote(options_fun), [options]), "#{key}")
        end
      end

      test "returns an error for options that are not a keyword list" do
        for options <- [nil, %{}, "x", [1], {:a}] do
          assert_error(apply(unquote(module), unquote(options_fun), [options]), inspect(options))
          assert_error(unquote(module).select(:form, :field, options), inspect(options))
        end
      end
    end
  end

  test "Territory and Locale work with their default options" do
    assert [{_name, _code} | _] = Localize.HTML.Territory.territory_options()
    assert length(Localize.HTML.Territory.territory_options()) == 252
    assert [{_name, _code} | _] = Localize.HTML.Locale.locale_options(locale: :en)
  end

  test "Locale lists the locales configured for Localize by default" do
    codes =
      Localize.HTML.Locale.locale_options(locale: :en) |> Enum.map(&elem(&1, 1)) |> Enum.sort()

    configured = Localize.supported_locales() |> Enum.map(&to_string/1) |> Enum.sort()

    assert codes == configured
  end

  test "Locale renders each locale in itself with locale: :identity" do
    assert [{"English", "en"}, {"français", "fr"}] =
             Localize.HTML.Locale.locale_options(locales: [:en, :fr], locale: :identity)

    html =
      Localize.HTML.Locale.select(:form, :field, locales: [:fr], locale: :identity)
      |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(lang="fr")
  end

  test "Month rejects a CLDR calendar type in place of a calendar module" do
    for calendar <- [:hebrew, "gregorian", 42, Enum] do
      assert {:error, %Localize.UnknownCalendarError{}} =
               Localize.HTML.Month.month_options(calendar: calendar)
    end
  end

  test "Month, Unit and Territory reject an unknown :style" do
    for module <- [Localize.HTML.Month, Localize.HTML.Unit, Localize.HTML.Territory] do
      assert {:error, %Localize.InvalidValueError{}} = module.select(:form, :field, style: :bogus)
    end
  end

  test "Month rejects a :year that is not an integer" do
    assert {:error, %Localize.InvalidValueError{}} =
             Localize.HTML.Month.month_options(year: "2026")
  end

  test "Subdivision rejects a :full_codes that is not a boolean" do
    assert {:error, %Localize.InvalidValueError{}} =
             Localize.HTML.Subdivision.subdivision_options(territory: :us, full_codes: "yes")
  end

  test "a selected value outside the list is added to it" do
    assert Enum.any?(
             Localize.HTML.Currency.currency_options(currencies: [:USD], selected: :EUR),
             fn {_name, code} -> code == "EUR" end
           )

    assert Enum.any?(
             Localize.HTML.Territory.territory_options(territories: [:US], selected: :FR),
             fn {_name, code} -> code == :FR end
           )

    assert Enum.any?(
             Localize.HTML.Unit.unit_options(units: [:meter], selected: :liter),
             fn {_name, code} -> code == "liter" end
           )
  end
end
