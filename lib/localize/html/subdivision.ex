defmodule Localize.HTML.Subdivision do
  @moduledoc """
  Generates HTML `<select>` tags and option lists for the subdivisions of a territory — US states, Canadian provinces, French departments and so on.

  Subdivision codes in CLDR carry their territory: California is `:usca`, not `:ca`. The territory is stripped from the option value, so a form receives `"ca"` and stores the subdivision as it is written in an address. The `:full_codes` option keeps the CLDR form where the value must remain globally unique.

  """

  @type select_options :: [
          {:territory, atom() | binary()}
          | {:locale, Localize.locale() | Localize.LanguageTag.t()}
          | {:collator, function()}
          | {:mapper, (subdivision() -> String.t())}
          | {:selected, atom() | binary()}
          | {:full_codes, boolean()}
        ]

  @typedoc """
  Subdivision type passed to a collator for ordering in the select box.

  """
  @type subdivision :: %{
          subdivision_code: String.t(),
          full_code: atom(),
          name: String.t()
        }

  @omit_from_select_options [:territory, :locale, :mapper, :collator, :full_codes]

  @doc """
  Returns a `<select>` tag of the subdivisions of a territory.

  ### Arguments

  * `form` is a `t:Phoenix.HTML.Form.t/0`.

  * `field` is the field name in `form`.

  * `options` is a keyword list of options.

  ### Options

  * `:territory` is the territory whose subdivisions are listed, for example `:US`. Required.

  * `:locale` is any locale returned by `Localize.all_locale_ids/0`. The default is `Localize.get_locale/0`.

  * `:full_codes` keeps the CLDR subdivision code (`:usca`) as the option value rather than stripping the territory (`"ca"`). The default is `false`.

  * `:selected` is the subdivision to mark as selected. Accepts either form of the code.

  * `:collator` orders the subdivisions. The default sorts by localized name using `Localize.Collation.sort/2`, so the order is correct for the locale.

  * `:mapper` builds each option from a `t:subdivision/0`. The default is `&{&1.name, &1.subdivision_code}`.

  Remaining options are passed to `PhoenixHTMLHelpers.Form.select/4`.

  ### Returns

  * A `t:Phoenix.HTML.safe/0` `<select>` tag, or

  * `{:error, exception}` if the territory or locale is invalid.

  ### Examples

      Localize.HTML.Subdivision.select(:address, :state, territory: :US)

      Localize.HTML.Subdivision.select(:address, :state, territory: :US, locale: :fr)

  """
  @spec select(
          form :: Phoenix.HTML.Form.t() | atom(),
          field :: Phoenix.HTML.Form.field() | atom(),
          select_options()
        ) :: Phoenix.HTML.safe() | {:error, {module(), String.t()}}

  def select(form, field, options \\ [])

  def select(form, field, options) when is_list(options) do
    select(form, field, validate_options(options), options[:selected])
  end

  @doc """
  Returns the subdivisions of a territory as a list of `{name, code}` tuples.

  Takes the same options as `select/3`.

  ### Returns

  * A list of `{name, code}` tuples, or

  * `{:error, exception}` if the territory or locale is invalid.

  ### Examples

      iex> {name, code} = Localize.HTML.Subdivision.subdivision_options(territory: :US) |> hd()
      iex> {name, code}
      {"Alabama", "al"}

  """
  @spec subdivision_options(select_options()) :: list(tuple()) | {:error, term()}

  def subdivision_options(options \\ [])

  def subdivision_options(options) when is_list(options) do
    case validate_options(options) do
      {:error, reason} -> {:error, reason}
      options -> build_subdivision_options(options)
    end
  end

  defp select(_form, _field, {:error, reason}, _selected) do
    {:error, reason}
  end

  defp select(form, field, options, _selected) do
    select_options =
      options
      |> Map.drop(@omit_from_select_options)
      |> Map.to_list()

    PhoenixHTMLHelpers.Form.select(
      form,
      field,
      build_subdivision_options(options),
      select_options
    )
  end

  defp default_options do
    Map.new(
      territory: nil,
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: &{&1.name, &1.subdivision_code},
      full_codes: false,
      selected: nil
    )
  end

  defp validate_options(options) do
    options = Map.new(options)

    with options <- Map.merge(default_options(), options),
         {:ok, options} <- validate_locale(options),
         {:ok, options} <- validate_territory(options) do
      options
    end
  end

  defp validate_locale(%{locale: locale} = options) do
    with {:ok, locale} <- Localize.validate_locale(locale) do
      {:ok, Map.put(options, :locale, locale)}
    end
  end

  defp validate_territory(%{territory: nil}) do
    {:error,
     Localize.InvalidValueError.exception(
       value: nil,
       expected: :territory,
       allowed_values: :territories_with_subdivisions
     )}
  end

  defp validate_territory(%{territory: territory} = options) do
    with {:ok, territory} <- Localize.validate_territory(territory) do
      {:ok, Map.put(options, :territory, territory)}
    end
  end

  # ── Building the options ─────────────────────────────────────────

  defp build_subdivision_options(%{territory: territory} = options) do
    territory
    |> subdivision_codes()
    |> Enum.map(&describe(&1, territory, options))
    |> options.collator.()
    |> Enum.map(options.mapper)
  end

  # `territory_subdivisions/0` is a containment tree: its keys are both
  # territories and subdivisions that themselves contain others. Only the
  # territory keys are wanted here, and a territory with no subdivisions at
  # all is an empty list rather than an error.
  defp subdivision_codes(territory) do
    Localize.SupplementalData.territory_subdivisions()
    |> Map.get(territory, [])
    |> List.wrap()
  end

  defp describe(full_code, territory, options) do
    %{
      full_code: full_code,
      subdivision_code: option_code(full_code, territory, options),
      name: name_for(full_code, territory, options.locale)
    }
  end

  defp option_code(full_code, _territory, %{full_codes: true}), do: full_code

  defp option_code(full_code, territory, _options) do
    strip_territory(full_code, territory)
  end

  # CLDR writes a subdivision code as its territory followed by the ISO 3166-2
  # code — `usca`, `frj`, `gbeng`. Every code under every real territory
  # carries its territory as a prefix, so stripping it is safe; the check is
  # kept so a future data shape cannot silently truncate a code.
  defp strip_territory(full_code, territory) do
    prefix = territory |> to_string() |> String.downcase()
    text = to_string(full_code)

    case String.split_at(text, String.length(prefix)) do
      {^prefix, rest} when rest != "" -> rest
      _other -> text
    end
  end

  # CLDR does not name every subdivision in every locale. Six of the 57 US
  # codes have no name in any locale — `usas`, `usgu`, `uspr` and the rest —
  # because CLDR models them as *territories* (American Samoa, Guam, Puerto
  # Rico), which have their own ISO 3166-1 codes. The chain is therefore:
  # the subdivision name, then the same name in the locale's parent, then the
  # territory display name, and finally the bare code.
  defp name_for(full_code, territory, locale) do
    with nil <- subdivision_name(full_code, locale),
         nil <- parent_subdivision_name(full_code, locale),
         nil <- territory_name(full_code, territory, locale) do
      to_string(full_code)
    end
  end

  defp subdivision_name(full_code, locale) do
    case Localize.Territory.Subdivision.subdivision_names_for(locale: locale) do
      {:ok, names} -> Map.get(names, full_code)
      {:error, _reason} -> nil
    end
  end

  defp parent_subdivision_name(full_code, locale) do
    case Localize.Locale.parent(locale) do
      {:ok, parent} -> subdivision_name(full_code, parent)
      {:error, _reason} -> nil
    end
  end

  # A subdivision code whose stripped form is itself an ISO 3166-1 territory
  # is named as that territory. Anything else has no territory to fall back to.
  defp territory_name(full_code, territory, locale) do
    with code <- strip_territory(full_code, territory),
         {:ok, subdivision_territory} <- Localize.validate_territory(code),
         {:ok, name} <- Localize.Territory.display_name(subdivision_territory, locale: locale) do
      name
    else
      _other -> nil
    end
  end

  # Sorting by name has to be locale-aware: an alphabetical sort of French
  # names under an English collation puts accented names in the wrong place.
  defp default_collator(subdivisions) do
    Enum.sort_by(subdivisions, & &1.name, &(Localize.Collation.compare(&1, &2) != :gt))
  end
end
