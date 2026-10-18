defmodule Localize.HTML.Territory do
  @moduledoc """
  Generates HTML `<select>` tags and option lists for localized territory display.

  Territories are displayed with their Unicode flag emoji and localized name. The list of territories, display style, sort order, and display format are all configurable.

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

  alias Localize.HTML.Options

  @omit_from_select_options [:territories, :locale, :mapper, :collator, :style]

  @doc """
  Generates an HTML select tag for a territory list that can be used with a `Phoenix.HTML.Form.t`.

  ### Arguments

  * `form` is a `t:Phoenix.HTML.Form.t/0` form.

  * `field` is a `t:Phoenix.HTML.Form.field/0` field.

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  * `:territories` defines the list of territories to be displayed in the select tag. The default is `Localize.Territory.individual_territories/0`: every current country and region, without groupings such as `:EU` or deprecated codes.

  * `:style` is the format of the territory name. The options are `:standard` (the default), `:short` and `:variant`.

  * `:locale` defines the locale to be used to localise the description of the territories. The default is the locale returned by `Localize.get_locale/0`.

  * `:collator` is a function used to sort the territories. The default collator sorts by name.

  * `:mapper` is a function that creates the text to be displayed in the select tag for each territory. The default function is `&({&1.flag <> " " <> &1.name, &1.territory_code})`.

  * `:selected` identifies the territory that is to be selected by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Returns

  * A `t:Phoenix.HTML.safe/0` select tag, or

  * `{:error, exception}` when an option is invalid.

  ### Examples

      iex> Localize.HTML.Territory.select(:my_form, :territory, selected: :AU)

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

        PhoenixHTMLHelpers.Form.select(
          form,
          field,
          build_territory_options(options),
          select_options
        )

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Generates a list of options for a territory list that can be used with `Phoenix.HTML.Form.options_for_select/2` or to create a `<datalist>`.

  ### Arguments

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Territory.select/3` for options.

  ### Returns

  * A list of `{display_name, territory_code}` tuples, or

  * `{:error, exception}` when an option is invalid.

  """
  @spec territory_options(select_options) :: list(tuple()) | {:error, Exception.t()}

  def territory_options(options \\ []) do
    with {:ok, options} <- validate_options(options) do
      build_territory_options(options)
    end
  end

  defp default_options do
    %{
      territories: Localize.Territory.individual_territories(),
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: &{&1.flag <> " " <> &1.name, &1.territory_code},
      style: :standard,
      selected: nil
    }
  end

  defp validate_options(options) do
    with {:ok, options} <- Options.merge(options, default_options()),
         {:ok, options} <- Options.locale(options),
         {:ok, options} <- Options.one_of(options, :style, Localize.Territory.known_styles()),
         {:ok, options} <- Options.function(options, :collator),
         {:ok, options} <- Options.function(options, :mapper),
         {:ok, options} <- Options.optional(options, :selected, &validate_territory/1) do
      Options.list(options, :territories, &validate_territory/1)
    end
  end

  defp validate_territory(territory) do
    Options.code(territory, :territory, &Localize.validate_territory/1)
  end

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
    case Localize.Territory.display_name(territory, options) do
      {:ok, name} -> name
      {:error, _reason} -> name_from_default_style(territory, options)
    end
  end

  # Not every territory has a name in every style, so a failed lookup
  # retries with the locale's default style before falling back to the
  # territory code itself.
  defp name_from_default_style(territory, options) do
    default_options = Keyword.delete(options, :style)

    case Localize.Territory.display_name(territory, default_options) do
      {:ok, name} -> name
      _error -> to_string(territory)
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
end
