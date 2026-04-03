defmodule Localize.HTML.Currency do
  @moduledoc """
  Implements an HTML Form select for localised currency display.

  """

  @type select_options :: [
          {:currencies, [atom() | binary(), ...]}
          | {:locale, Localize.locale() | Localize.LanguageTag.t()}
          | {:collator, function()}
          | {:mapper, (Localize.Currency.t() -> String.t())}
          | {:selected, atom() | binary()}
        ]

  @doc """
  Generate an HTML select tag for a currency list
  that can be used with a `Phoenix.HTML.Form.t`.

  ### Arguments

  * A `t:Phoenix.HTML.Form.t/0` form.

  * A `t:Phoenix.HTML.Form.field/0` field.

  * A `t:Keyword.t/0` list of options.

  ### Options

  * `:currencies` defines the list of currencies to be displayed
    in the select tag. The default is
    `Localize.Currency.known_currency_codes/0`.

  * `:locale` defines the locale to be used to localise the
    description of the currencies. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:collator` is a function used to sort the currencies
    in the selection list. The default collator sorts by name.

  * `:mapper` is a function that creates the text to be displayed
    in the select tag for each currency. The default function is
    `&({&1.code <> " - " <> &1.name, &1.code})`.

  * `:selected` identifies the currency that is to be selected
    by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Examples

      iex> Localize.HTML.Currency.select(:my_form, :currency, selected: :USD)

  """
  @spec select(
          form :: Phoenix.HTML.Form.t(),
          field :: Phoenix.HTML.Form.field(),
          select_options
        ) ::
          Phoenix.HTML.safe()
          | {:error, {module(), binary()}}

  def select(form, field, options \\ [])

  def select(form, field, options) when is_list(options) do
    select(form, field, validate_options(options), options[:selected])
  end

  @doc """
  Generate a list of options for a currency list that can be used
  with `Phoenix.HTML.Form.options_for_select/2` or to create a
  `<datalist>`.

  ### Arguments

  * A `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Currency.select/3` for options.

  """
  @spec currency_options(select_options) :: list(tuple()) | {:error, {module(), binary()}}

  def currency_options(options \\ [])

  def currency_options(options) when is_list(options) do
    options
    |> validate_options()
    |> build_currency_options()
  end

  defp select(_form, _field, {:error, reason}, _selected) do
    {:error, reason}
  end

  @omit_from_select_options [:currencies, :locale, :mapper, :collator]

  defp select(form, field, options, _selected) do
    select_options =
      options
      |> Map.drop(@omit_from_select_options)
      |> Map.to_list()

    options = build_currency_options(options)

    PhoenixHTMLHelpers.Form.select(form, field, options, select_options)
  end

  defp validate_options(options) do
    options = Map.new(options)

    with options <- Map.merge(default_options(), options),
         {:ok, options} <- validate_locale(options),
         {:ok, options} <- validate_selected(options),
         {:ok, options} <- validate_currencies(options) do
      options
    end
  end

  defp default_options do
    Map.new(
      currencies: Localize.Currency.known_currency_codes(),
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: &{&1.code <> " - " <> &1.name, &1.code},
      selected: nil
    )
  end

  defp default_collator(currencies) do
    Enum.sort(currencies, &(&1.name < &2.name))
  end

  defp validate_selected(%{selected: nil} = options) do
    {:ok, options}
  end

  defp validate_selected(%{selected: selected} = options) do
    with {:ok, currency} <- Localize.Currency.validate_currency(selected) do
      {:ok, Map.put(options, :selected, currency)}
    end
  end

  defp validate_currencies(%{currencies: currencies} = options) do
    validate_currencies(currencies, options)
  end

  defp validate_currencies(currencies) when is_list(currencies) do
    Enum.reduce_while(currencies, [], fn currency, acc ->
      case Localize.Currency.validate_currency(currency) do
        {:ok, currency} -> {:cont, [currency | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_currencies(currencies, options) do
    case validate_currencies(currencies) do
      {:error, reason} -> {:error, reason}
      currencies -> {:ok, Map.put(options, :currencies, Enum.reverse(currencies))}
    end
  end

  defp validate_locale(options) do
    with {:ok, locale} <- Localize.validate_locale(options[:locale]) do
      options
      |> Map.put(:locale, locale)
      |> wrap(:ok)
    end
  end

  defp wrap(term, atom), do: {atom, term}

  defp maybe_include_selected_currency(%{selected: nil} = options) do
    options
  end

  defp maybe_include_selected_currency(%{currencies: currencies, selected: selected} = options) do
    if Enum.any?(currencies, &(&1 == selected)) do
      options
    else
      Map.put(options, :currencies, [selected | currencies])
    end
  end

  defp build_currency_options(options) when is_map(options) do
    options = maybe_include_selected_currency(options)

    currencies = Map.fetch!(options, :currencies)
    collator = Map.fetch!(options, :collator)
    mapper = Map.fetch!(options, :mapper)
    locale = Map.fetch!(options, :locale)

    currencies
    |> Enum.map(fn code ->
      case Localize.Currency.currency_for_code(code, locale: locale) do
        {:ok, currency} -> currency
        _ -> %{code: to_string(code), name: to_string(code)}
      end
    end)
    |> collator.()
    |> Enum.map(&mapper.(&1))
  end
end
