defmodule Localize.HTML.Territory do
  @moduledoc """
  Implements an HTML Form select for localised territory display.

  """

  @type select_options :: [
          {:territories, [atom() | binary(), ...]}
          | {:locale, Localize.locale() | Localize.LanguageTag.t()}
          | {:collator, function()}
          | {:mapper, (territory() -> String.t())}
          | {:selected, atom() | binary()}
          | {:style, :standard | :short | :variant}
        ]

  @typedoc """
  Territory type passed to a collator for ordering in the select box.

  """
  @type territory :: %{
          territory_code: atom(),
          name: String.t(),
          flag: String.t()
        }

  @omit_from_select_options [:territories, :locale, :mapper, :collator, :style]

  @doc """
  Generate an HTML select tag for a territory list
  that can be used with a `Phoenix.HTML.Form.t`.

  ### Arguments

  * A `t:Phoenix.HTML.Form.t/0` form.

  * A `t:Phoenix.HTML.Form.field/0` field.

  * A `t:Keyword.t/0` list of options.

  ### Options

  * `:territories` defines the list of territories to be displayed
    in the select tag. The default is
    `Localize.Territory.country_codes/0`.

  * `:style` is the format of the territory name. The options are
    `:standard` (the default), `:short` and `:variant`.

  * `:locale` defines the locale to be used to localise the
    description of the territories. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:collator` is a function used to sort the territories.
    The default collator sorts by name.

  * `:mapper` is a function that creates the text to be displayed
    in the select tag for each territory. The default function is
    `&({&1.flag <> " " <> &1.name, &1.territory_code})`.

  * `:selected` identifies the territory that is to be selected
    by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Examples

      iex> Localize.HTML.Territory.select(:my_form, :territory, selected: :AU)

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
  Generate a list of options for a territory list that can be used
  with `Phoenix.HTML.Form.options_for_select/2` or to create a
  `<datalist>`.

  ### Arguments

  * A `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Territory.select/3` for options.

  """
  @spec territory_options(select_options) :: list(tuple()) | {:error, {module(), binary()}}

  def territory_options(options \\ [])

  def territory_options(options) when is_list(options) do
    options
    |> validate_options()
    |> build_territory_options()
  end

  defp select(_form, _field, {:error, reason}, _selected) do
    {:error, reason}
  end

  defp select(form, field, options, _selected) do
    select_options =
      options
      |> Map.drop(@omit_from_select_options)
      |> Map.to_list()

    options = build_territory_options(options)

    PhoenixHTMLHelpers.Form.select(form, field, options, select_options)
  end

  defp default_options do
    Map.new(
      territories: Localize.Territory.country_codes(),
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: &{&1.flag <> " " <> &1.name, &1.territory_code},
      selected: nil
    )
  end

  defp validate_options(options) do
    options = Map.new(options)

    with options <- Map.merge(default_options(), options),
         {:ok, options} <- validate_locale(options),
         {:ok, options} <- validate_selected(options),
         {:ok, options} <- validate_territories(options) do
      options
    end
  end

  defp validate_selected(%{selected: nil} = options) do
    {:ok, options}
  end

  defp validate_selected(%{selected: selected} = options) do
    with {:ok, territory} <- Localize.validate_territory(selected) do
      {:ok, Map.put(options, :selected, territory)}
    end
  end

  defp validate_territories(%{territories: territories} = options) do
    validate_territories(territories, options)
  end

  defp validate_territories(territories) when is_list(territories) do
    Enum.reduce_while(territories, [], fn territory, acc ->
      case Localize.validate_territory(territory) do
        {:ok, territory} -> {:cont, [territory | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_territories(territories, options) do
    case validate_territories(territories) do
      {:error, reason} -> {:error, reason}
      territories -> {:ok, Map.put(options, :territories, Enum.reverse(territories))}
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

  defp maybe_include_selected_territory(%{selected: nil} = options) do
    options
  end

  defp maybe_include_selected_territory(%{territories: territories, selected: selected} = options) do
    if Enum.any?(territories, &(&1 == selected)) do
      options
    else
      Map.put(options, :territories, [selected | territories])
    end
  end

  defp build_territory_options(options) when is_map(options) do
    options = maybe_include_selected_territory(options)

    territories = Map.fetch!(options, :territories)
    collator = Map.fetch!(options, :collator)
    mapper = Map.fetch!(options, :mapper)

    territories
    |> Enum.map(&territory_info(&1, options))
    |> collator.()
    |> Enum.map(&mapper.(&1))
  end

  defp default_collator(territories) do
    Enum.sort(territories, &(&1.name < &2.name))
  end

  defp territory_info(territory, options) do
    info_opts = info_options(options)
    name = name_from_territory(territory, info_opts)
    flag = flag_from_territory(territory)

    %{territory_code: territory, name: name, flag: flag}
  end

  defp name_from_territory(territory, options) do
    with {:ok, name} <- Localize.Territory.display_name(territory, options) do
      name
    else
      {:error, _} ->
        default_options = Keyword.delete(options, :style)

        case Localize.Territory.display_name(territory, default_options) do
          {:ok, name} -> name
          _ -> to_string(territory)
        end
    end
  end

  defp flag_from_territory(territory) do
    case Localize.Territory.unicode_flag(territory) do
      {:ok, flag} -> flag
      _ -> " "
    end
  end

  defp info_options(%{locale: locale, style: style}) do
    [locale: locale, style: style]
  end

  defp info_options(%{locale: locale}) do
    [locale: locale]
  end

  defp info_options(%{style: style}) do
    [style: style]
  end

  defp info_options(_options), do: []
end
