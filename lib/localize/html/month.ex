defmodule Localize.HTML.Month do
  @moduledoc """
  Generates HTML `<select>` tags and option lists for localized month name display.

  Month names are sourced from CLDR calendar data and localized according to the current or specified locale. The display style (wide, abbreviated, narrow), calendar system, and sort order are all configurable.

  """

  @type select_options :: [
          {:months, [pos_integer(), ...]}
          | {:locale, Localize.locale() | Localize.LanguageTag.t()}
          | {:calendar, module()}
          | {:year, Calendar.year()}
          | {:style, :wide | :abbreviated | :narrow}
          | {:collator, function()}
          | {:mapper, function()}
          | {:selected, pos_integer()}
        ]

  @omit_from_select_options [:months, :locale, :mapper, :collator, :calendar, :year, :style]

  @doc """
  Generates an HTML select tag for a month name list that can be used with a `Phoenix.HTML.Form.t`.

  ### Arguments

  * `form` is a `t:Phoenix.HTML.Form.t/0` form.

  * `field` is a `t:Phoenix.HTML.Form.field/0` field.

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  * `:months` defines the list of month numbers to be displayed. The default is `1..12`.

  * `:calendar` is the calendar from which the month names are derived. The default is `Calendar.ISO`.

  * `:year` is the year from which the number of months is derived. The default is the current year.

  * `:locale` defines the locale used to localise the month names. The default is the locale returned by `Localize.get_locale/0`.

  * `:style` is the format of the month name. The options are `:wide` (the default), `:abbreviated` and `:narrow`.

  * `:collator` is a function used to sort the months. The default collator preserves month order.

  * `:mapper` is a function that creates the text to be displayed in the select tag for each month. It receives a tuple `{month_name, month_number}`. The default is the identity function.

  * `:selected` identifies the month to be selected by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Returns

  * A `t:Phoenix.HTML.safe/0` select tag.

  ### Examples

      iex> Localize.HTML.Month.select(:my_form, :month, selected: 1)

  """
  @spec select(
          form :: Phoenix.HTML.Form.t(),
          field :: Phoenix.HTML.Form.field(),
          select_options
        ) :: Phoenix.HTML.safe()

  def select(form, field, options \\ [])

  def select(form, field, options) when is_list(options) do
    options = validate_options(options)
    month_options = build_month_options(options)

    select_options =
      options
      |> Map.drop(@omit_from_select_options)
      |> Map.to_list()

    PhoenixHTMLHelpers.Form.select(form, field, month_options, select_options)
  end

  @doc """
  Generates a list of options for a month list that can be used with `Phoenix.HTML.Form.options_for_select/2` or to create a `<datalist>`.

  ### Arguments

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Month.select/3` for options.

  ### Returns

  * A list of `{month_name, month_number}` tuples.

  """
  @spec month_options(select_options) :: list(tuple())

  def month_options(options \\ [])

  def month_options(options) when is_list(options) do
    options
    |> validate_options()
    |> build_month_options()
  end

  defp validate_options(options) do
    options = Map.new(options)
    Map.merge(default_options(), options)
  end

  defp default_options do
    Map.new(
      months: Enum.to_list(1..12),
      locale: Localize.get_locale(),
      calendar: Calendar.ISO,
      year: Date.utc_today().year,
      style: :wide,
      collator: & &1,
      mapper: & &1,
      selected: nil
    )
  end

  defp build_month_options(options) do
    months = Map.fetch!(options, :months)
    locale = Map.fetch!(options, :locale)
    style = Map.fetch!(options, :style)
    collator = Map.fetch!(options, :collator)
    mapper = Map.fetch!(options, :mapper)

    locale_id =
      case locale do
        %Localize.LanguageTag{cldr_locale_id: id} -> id
        other -> other
      end

    month_names = get_month_names(locale_id, style)

    months
    |> Enum.map(fn month_number ->
      name = Map.get(month_names, month_number, "Month #{month_number}")
      {name, month_number}
    end)
    |> collator.()
    |> Enum.map(&mapper.(&1))
  end

  defp get_month_names(locale_id, style) do
    calendar_key = calendar_style_key(style)

    case Localize.Locale.get(locale_id, [
           :dates,
           :calendars,
           :gregorian,
           :months,
           :format,
           calendar_key
         ]) do
      {:ok, months} when is_map(months) ->
        months

      _ ->
        Enum.into(1..12, %{}, fn n -> {n, "Month #{n}"} end)
    end
  end

  defp calendar_style_key(:wide), do: :wide
  defp calendar_style_key(:abbreviated), do: :abbreviated
  defp calendar_style_key(:narrow), do: :narrow
  defp calendar_style_key(_), do: :wide
end
