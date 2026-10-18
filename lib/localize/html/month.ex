defmodule Localize.HTML.Month do
  @moduledoc """
  Generates HTML `<select>` tags and option lists for localized month name display.

  Month names are sourced from CLDR calendar data and localized according to the current or specified locale. The display style (wide, abbreviated, narrow), calendar system, and sort order are all configurable.

  """

  @type select_options :: [
          {:months, [pos_integer(), ...]}
          | {:locale, Localize.locale() | Localize.LanguageTag.t()}
          | {:calendar, Calendar.calendar()}
          | {:year, Calendar.year()}
          | {:style, :wide | :abbreviated | :narrow}
          | {:collator, function()}
          | {:mapper, function()}
          | {:selected, pos_integer()}
        ]

  alias Localize.HTML.Options

  @omit_from_select_options [:months, :locale, :mapper, :collator, :calendar, :year, :style]

  @styles [:wide, :abbreviated, :narrow]

  @doc """
  Generates an HTML select tag for a month name list that can be used with a `Phoenix.HTML.Form.t`.

  ### Arguments

  * `form` is a `t:Phoenix.HTML.Form.t/0` form.

  * `field` is a `t:Phoenix.HTML.Form.field/0` field.

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  * `:months` defines the list of month numbers, from 1 to 13, to be displayed. The default is `1..12`.

  * `:calendar` is the calendar module from which the month names are derived. The default is `Calendar.ISO`, which renders Gregorian labels. If the calendar module exports `cldr_calendar_type/0`, the returned atom selects the CLDR calendar used for the labels (for example, `Calendrical.Hebrew` returns `:hebrew`). Calendars without that function fall back to Gregorian labels. Anything that is not a calendar module, including a CLDR calendar type such as `:hebrew`, returns an error.

  * `:year` is the year from which the number of months is derived. The default is the current year.

  * `:locale` defines the locale used to localise the month names. The default is the locale returned by `Localize.get_locale/0`.

  * `:style` is the format of the month name. The options are `:wide` (the default), `:abbreviated` and `:narrow`.

  * `:collator` is a function used to sort the months. The default collator preserves month order.

  * `:mapper` is a function that creates the text to be displayed in the select tag for each month. It receives a tuple `{month_name, month_number}`. The default is the identity function.

  * `:selected` identifies the month to be selected by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Returns

  * A `t:Phoenix.HTML.safe/0` select tag, or

  * `{:error, exception}` when an option is invalid.

  ### Examples

      iex> Localize.HTML.Month.select(:my_form, :month, selected: 1)

  """
  @spec select(
          form :: Phoenix.HTML.Form.t(),
          field :: Phoenix.HTML.Form.field(),
          select_options
        ) :: Phoenix.HTML.safe() | {:error, Exception.t()}

  def select(form, field, options \\ []) do
    case validate_options(options) do
      {:ok, options} ->
        select_options =
          options
          |> Map.drop(@omit_from_select_options)
          |> Map.to_list()

        PhoenixHTMLHelpers.Form.select(form, field, build_month_options(options), select_options)

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Generates a list of options for a month list that can be used with `Phoenix.HTML.Form.options_for_select/2` or to create a `<datalist>`.

  ### Arguments

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Month.select/3` for options.

  ### Returns

  * A list of `{month_name, month_number}` tuples, or

  * `{:error, exception}` when an option is invalid.

  """
  @spec month_options(select_options) :: list(tuple()) | {:error, Exception.t()}

  def month_options(options \\ []) do
    with {:ok, options} <- validate_options(options) do
      build_month_options(options)
    end
  end

  defp validate_options(options) do
    with {:ok, options} <- Options.merge(options, default_options()),
         {:ok, options} <- Options.locale(options),
         {:ok, options} <- Options.one_of(options, :style, @styles),
         {:ok, options} <- Options.function(options, :collator),
         {:ok, options} <- Options.function(options, :mapper),
         {:ok, options} <- validate_calendar(options),
         {:ok, options} <- validate_year(options),
         {:ok, options} <- Options.optional(options, :selected, &validate_month/1) do
      Options.list(options, :months, &validate_month/1)
    end
  end

  defp default_options do
    %{
      months: Enum.to_list(1..12),
      locale: Localize.get_locale(),
      calendar: Calendar.ISO,
      year: Date.utc_today().year,
      style: :wide,
      collator: & &1,
      mapper: & &1,
      selected: nil
    }
  end

  # A calendar is a module implementing the `Calendar` behaviour. A CLDR
  # calendar type such as `:hebrew` is not a calendar and is rejected.
  defp validate_calendar(%{calendar: calendar} = options) do
    if is_atom(calendar) and Code.ensure_loaded?(calendar) and
         function_exported?(calendar, :days_in_month, 2) do
      {:ok, options}
    else
      {:error, Localize.UnknownCalendarError.exception(calendar: calendar)}
    end
  end

  defp validate_year(%{year: year} = options) when is_integer(year), do: {:ok, options}
  defp validate_year(%{year: year}), do: Options.invalid(year, :year)

  # No calendar has more than 13 months.
  defp validate_month(month) when month in 1..13, do: {:ok, month}
  defp validate_month(month), do: Options.invalid(month, :month)

  defp build_month_options(options) do
    months = Map.fetch!(options, :months)
    locale = Map.fetch!(options, :locale)
    style = Map.fetch!(options, :style)
    collator = Map.fetch!(options, :collator)
    mapper = Map.fetch!(options, :mapper)
    calendar = Map.fetch!(options, :calendar)

    # `validate_locale/1` resolves the option to a language tag before this
    # runs, so the CLDR id is always reachable directly.
    month_names = get_month_names(locale.cldr_locale_id, style, calendar)

    months
    |> Enum.map(fn month_number ->
      name = Map.get(month_names, month_number, "Month #{month_number}")
      {name, month_number}
    end)
    |> collator.()
    |> Enum.map(&mapper.(&1))
  end

  defp get_month_names(locale_id, style, calendar) do
    calendar_key = calendar_style_key(style)
    calendar_type = calendar_type(calendar)

    case Localize.Locale.get(locale_id, [
           :dates,
           :calendars,
           calendar_type,
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

  defp calendar_type(calendar) do
    if function_exported?(calendar, :cldr_calendar_type, 0) do
      calendar.cldr_calendar_type()
    else
      :gregorian
    end
  end

  defp calendar_style_key(:wide), do: :wide
  defp calendar_style_key(:abbreviated), do: :abbreviated
  defp calendar_style_key(:narrow), do: :narrow
end
