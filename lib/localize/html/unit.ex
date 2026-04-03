defmodule Localize.HTML.Unit do
  @moduledoc """
  Implements an HTML Form select for localised unit display.

  """

  @type select_options :: [
          {:units, [atom() | binary(), ...]}
          | {:locale, Localize.locale() | Localize.LanguageTag.t()}
          | {:collator, function()}
          | {:mapper, (tuple() -> String.t())}
          | {:selected, atom() | binary()}
          | {:style, :long | :short | :narrow}
        ]

  @doc """
  Generate an HTML select tag for a unit list
  that can be used with a `t:Phoenix.HTML.Form.t/0`.

  ### Arguments

  * A `t:Phoenix.HTML.Form.t/0` form.

  * A `t:Phoenix.HTML.Form.field/0` field.

  * A `t:Keyword.t/0` list of options.

  ### Options

  * `:units` is a list of units to be displayed in the select.

  * `:style` is the style of unit name to be displayed. The
    options are `:long`, `:short` and `:narrow`. The default
    is `:long`.

  * `:locale` defines the locale to be used to localise the
    description of the units. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:collator` is a function used to sort the units. The
    default collator sorts by display name.

  * `:mapper` is a function that creates the text to be displayed
    in the select tag for each unit. It receives a tuple
    `{display_name, unit_code}`. The default is the identity
    function.

  * `:selected` identifies the unit to be selected by default
    in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Examples

      iex> Localize.HTML.Unit.select(:my_form, :unit, selected: :foot)

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
  Generate a list of options for a unit list that can be used
  with `Phoenix.HTML.Form.options_for_select/2` or to create a
  `<datalist>`.

  ### Arguments

  * A `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Unit.select/3` for options.

  """
  @spec unit_options(select_options) :: list(tuple()) | {:error, {module(), binary()}}

  def unit_options(options \\ [])

  def unit_options(options) when is_list(options) do
    options
    |> validate_options()
    |> build_unit_options()
  end

  defp select(_form, _field, {:error, reason}, _selected) do
    {:error, reason}
  end

  @omit_from_select_options [:units, :locale, :mapper, :collator, :style]

  defp select(form, field, options, _selected) do
    select_options =
      options
      |> Map.drop(@omit_from_select_options)
      |> Map.to_list()

    options = build_unit_options(options)

    PhoenixHTMLHelpers.Form.select(form, field, options, select_options)
  end

  defp validate_options(options) do
    with options <- Map.merge(default_options(), Map.new(options)),
         {:ok, options} <- validate_locale(options),
         {:ok, options} <- validate_selected(options) do
      options
    end
  end

  defp default_options do
    Map.new(
      units: default_unit_list(),
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: & &1,
      style: :long,
      selected: nil
    )
  end

  defp default_collator(units) do
    Enum.sort(units, fn {name_1, _}, {name_2, _} -> name_1 < name_2 end)
  end

  defp validate_selected(%{selected: nil} = options) do
    {:ok, options}
  end

  defp validate_selected(%{selected: selected} = options) do
    {:ok, Map.put(options, :selected, to_string(selected))}
  end

  defp validate_locale(options) do
    with {:ok, locale} <- Localize.validate_locale(options[:locale]) do
      options
      |> Map.put(:locale, locale)
      |> wrap(:ok)
    end
  end

  defp wrap(term, atom), do: {atom, term}

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
        name when is_binary(name) -> name
        _ -> to_string(unit)
      end

    unit_code = to_string(unit)
    {display_name, unit_code}
  end

  defp default_unit_list do
    Localize.Unit.known_units_by_category()
    |> Enum.flat_map(fn {_category, units} -> units end)
  end
end
