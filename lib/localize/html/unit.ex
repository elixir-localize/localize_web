defmodule Localize.HTML.Unit do
  @moduledoc """
  Generates HTML `<select>` tags and option lists for localized unit-of-measure display.

  Units are displayed with their localized display name. The list of units, display style (long, short, narrow), sort order, and display format are all configurable.

  """

  @type select_options :: [
          {:units, [atom() | binary(), ...]}
          | {:locale, Localize.locale() | Localize.LanguageTag.t()}
          | {:collator, function()}
          | {:mapper, (tuple() -> String.t())}
          | {:selected, atom() | binary()}
          | {:style, :long | :short | :narrow}
        ]

  alias Localize.HTML.Options

  @omit_from_select_options [:units, :locale, :mapper, :collator, :style]

  @styles [:long, :short, :narrow]

  @doc """
  Generates an HTML select tag for a unit list that can be used with a `t:Phoenix.HTML.Form.t/0`.

  ### Arguments

  * `form` is a `t:Phoenix.HTML.Form.t/0` form.

  * `field` is a `t:Phoenix.HTML.Form.field/0` field.

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  * `:units` is a list of units to be displayed in the select.

  * `:style` is the style of unit name to be displayed. The options are `:long`, `:short` and `:narrow`. The default is `:long`.

  * `:locale` defines the locale to be used to localise the description of the units. The default is the locale returned by `Localize.get_locale/0`.

  * `:collator` is a function used to sort the units. The default collator sorts by display name.

  * `:mapper` is a function that creates the text to be displayed in the select tag for each unit. It receives a tuple `{display_name, unit_code}`. The default is the identity function.

  * `:selected` identifies the unit to be selected by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Returns

  * A `t:Phoenix.HTML.safe/0` select tag, or

  * `{:error, exception}` when an option is invalid.

  ### Examples

      iex> Localize.HTML.Unit.select(:my_form, :unit, selected: :foot)

  """
  @spec select(
          form :: Phoenix.HTML.Form.t(),
          field :: Phoenix.HTML.Form.field(),
          select_options
        ) ::
          Phoenix.HTML.safe()
          | {:error, Exception.t()}

  def select(form, field, options \\ []) do
    case validate_options(options) do
      {:ok, options} ->
        select_options =
          options
          |> Map.drop(@omit_from_select_options)
          |> Map.to_list()

        PhoenixHTMLHelpers.Form.select(form, field, build_unit_options(options), select_options)

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Generates a list of options for a unit list that can be used with `Phoenix.HTML.Form.options_for_select/2` or to create a `<datalist>`.

  ### Arguments

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Unit.select/3` for options.

  ### Returns

  * A list of `{display_name, unit_code}` tuples, or

  * `{:error, exception}` when an option is invalid.

  """
  @spec unit_options(select_options) :: list(tuple()) | {:error, Exception.t()}

  def unit_options(options \\ []) do
    with {:ok, options} <- validate_options(options) do
      build_unit_options(options)
    end
  end

  defp validate_options(options) do
    with {:ok, options} <- Options.merge(options, default_options()),
         {:ok, options} <- Options.locale(options),
         {:ok, options} <- Options.one_of(options, :style, @styles),
         {:ok, options} <- Options.function(options, :collator),
         {:ok, options} <- Options.function(options, :mapper),
         {:ok, options} <- Options.optional(options, :selected, &validate_unit/1) do
      Options.list(options, :units, &validate_unit/1)
    end
  end

  defp default_options do
    %{
      units: default_unit_list(),
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: & &1,
      style: :long,
      selected: nil
    }
  end

  defp default_collator(units) do
    Enum.sort(units, fn {name_1, _}, {name_2, _} -> name_1 < name_2 end)
  end

  defp validate_unit(unit) when is_atom(unit) or is_binary(unit) do
    unit = to_string(unit)

    with {:ok, _unit} <- Localize.Unit.new(unit) do
      {:ok, unit}
    end
  end

  defp validate_unit(unit), do: Options.invalid(unit, :unit)

  defp maybe_include_selected_unit(%{selected: nil} = options) do
    options
  end

  defp maybe_include_selected_unit(%{units: units, selected: selected} = options) do
    if Enum.any?(units, &(to_string(&1) == to_string(selected))) do
      options
    else
      Map.put(options, :units, [selected | units])
    end
  end

  defp build_unit_options(options) when is_map(options) do
    options = maybe_include_selected_unit(options)

    units = Map.fetch!(options, :units)
    collator = Map.fetch!(options, :collator)
    mapper = Map.fetch!(options, :mapper)
    options_list = Map.to_list(options)

    units
    |> Enum.map(&to_selection_tuple(&1, options_list))
    |> collator.()
    |> Enum.map(&mapper.(&1))
  end

  defp to_selection_tuple(unit, options) do
    display_name =
      case Localize.Unit.display_name(to_string(unit), options) do
        {:ok, name} -> name
        {:error, _} -> to_string(unit)
      end

    unit_code = to_string(unit)
    {display_name, unit_code}
  end

  defp default_unit_list do
    Localize.Unit.known_units_by_category()
    |> Enum.flat_map(fn {_category, units} -> units end)
  end
end
