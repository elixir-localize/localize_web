defmodule Localize.HTML.Locale do
  @moduledoc """
  Generates HTML `<select>` tags and option lists for localized locale display.

  Locales are displayed with their localized display name. A special `:identity` mode renders each locale's name in its own language. The list of locales, sort order, and display format are all configurable.

  """

  @type select_options :: [
          {:locales, [atom() | binary(), ...]}
          | {:locale, Localize.locale() | Localize.LanguageTag.t() | :identity}
          | {:collator, function()}
          | {:mapper, function()}
          | {:selected, atom() | binary()}
          | {atom(), any()}
        ]

  @type locale :: %{
          locale: String.t(),
          display_name: String.t(),
          language_tag: Localize.LanguageTag.t()
        }

  @type mapper :: (locale() -> String.t())

  @identity :identity

  @dont_include_default [:"en-001", :root, :und]

  @doc """
  Generates an HTML select tag for a locale list that can be used with a `Phoenix.HTML.Form.t`.

  ### Arguments

  * `form` is a `t:Phoenix.HTML.Form.t/0` form.

  * `field` is a `t:Phoenix.HTML.Form.field/0` field.

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  * `:locales` defines the list of locales to be displayed in the select tag. The default is `Localize.all_locale_ids/0` with meta locales excluded.

  * `:locale` may be set to `:identity` to render each locale in `:locales`
    in its own locale. Otherwise display names are rendered in the current
    process locale returned by `Localize.get_locale/0`.

  * `:collator` is a function used to sort the locales. The default collator sorts by display name.

  * `:mapper` is a function that creates the text to be displayed in the select tag for each locale. It receives a map with `:display_name`, `:locale` and `:language_tag` keys. The default mapper is `&{&1.display_name, &1.locale}`.

  * `:selected` identifies the locale to be selected by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Returns

  * A `t:Phoenix.HTML.safe/0` select tag, or

  * `{:error, {module(), binary()}}` if validation fails.

  ### Examples

      iex> Localize.HTML.Locale.select(:my_form, :locale_list, selected: "en")

  """
  @spec select(
          form :: Phoenix.HTML.Form.t(),
          field :: Phoenix.HTML.Form.field(),
          select_options
        ) ::
          Phoenix.HTML.safe() | {:error, {module(), binary()}}

  def select(form, field, options \\ [])

  def select(form, field, options) when is_list(options) do
    select(form, field, validate_options(options), options[:selected])
  end

  @doc """
  Generates a list of options for a locale list that can be used with `Phoenix.HTML.Form.options_for_select/2` or to create a `<datalist>`.

  ### Arguments

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Locale.select/3` for options.

  ### Returns

  * A list of `{display_name, locale_string}` tuples, or

  * `{:error, {module(), binary()}}` if validation fails.

  """
  @spec locale_options(select_options) :: list(tuple()) | {:error, {module(), binary()}}

  def locale_options(options \\ [])

  def locale_options(options) when is_list(options) do
    options
    |> validate_options()
    |> build_locale_options()
  end

  defp select(_form, _field, {:error, reason}, _selected) do
    {:error, reason}
  end

  @omit_from_select_options [
    :locales,
    :locale,
    :mapper,
    :collator,
    :add_likely_subtags,
    :prefer,
    :compound_locale
  ]

  defp select(form, field, %{locale: locale} = options, _selected) do
    select_options =
      options
      |> Map.drop(@omit_from_select_options)
      |> Map.to_list()

    options = build_locale_options(options)
    {options, select_options} = add_lang_attribute(locale, options, select_options)

    PhoenixHTMLHelpers.Form.select(form, field, options, select_options)
  end

  defp add_lang_attribute(@identity, options, select_options) do
    options = Enum.map(options, fn {key, value} -> [key: key, value: value, lang: value] end)
    {options, select_options}
  end

  defp add_lang_attribute(locale, options, select_options) do
    {options, Keyword.put(select_options, :lang, locale)}
  end

  defp validate_options(options) do
    options = Map.new(options)

    with options <- Map.merge(default_options(), options),
         {:ok, options} <- validate_locale(options.locale, options),
         {:ok, options} <- validate_selected(options.selected, options),
         {:ok, options} <- validate_locales(options.locales, options),
         {:ok, options} <- validate_identity_locales(options.locale, options) do
      options
    end
  end

  defp default_options do
    Map.new(
      locales: nil,
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: &{&1.display_name, &1.locale},
      selected: nil,
      add_likely_subtags: false,
      compound_locale: false,
      prefer: :default
    )
  end

  defp default_collator(locales) do
    Enum.sort(locales, &(&1.display_name < &2.display_name))
  end

  defp validate_selected(nil, options) do
    {:ok, options}
  end

  defp validate_selected(selected, options) do
    case Localize.validate_locale(to_string(selected)) do
      {:ok, locale} -> {:ok, Map.put(options, :selected, locale)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_locales(nil, options) do
    default_locales = Localize.all_locale_ids() -- @dont_include_default
    validate_locales(default_locales, options)
  end

  defp validate_locales(locales, options) when is_list(locales) do
    Enum.reduce_while(locales, [], fn locale, acc ->
      case Localize.validate_locale(to_string(locale)) do
        {:ok, locale} -> {:cont, [locale | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      locales -> {:ok, Map.put(options, :locales, locales)}
    end
  end

  defp validate_identity_locales(@identity, options) do
    Enum.reduce_while(options.locales, {:ok, options}, fn locale, acc ->
      case Localize.validate_locale(locale) do
        {:ok, _locale} -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_identity_locales(_locale, options) do
    {:ok, options}
  end

  defp validate_locale(:identity, options) do
    {:ok, options}
  end

  defp validate_locale(locale, options) do
    with {:ok, locale} <- Localize.validate_locale(locale) do
      options
      |> Map.put(:locale, locale)
      |> wrap(:ok)
    end
  end

  defp wrap(term, atom), do: {atom, term}

  defp maybe_include_selected_locale(%{selected: nil} = options) do
    options
  end

  defp maybe_include_selected_locale(%{locales: locales, selected: selected} = options) do
    if Enum.any?(locales, &(&1.canonical_locale_id == selected.canonical_locale_id)) do
      options
    else
      Map.put(options, :locales, [selected | locales])
    end
  end

  defp build_locale_options(options) when is_map(options) do
    options = maybe_include_selected_locale(options)

    locales = Map.fetch!(options, :locales)
    locale = Map.fetch!(options, :locale)
    collator = Map.fetch!(options, :collator)
    mapper = Map.fetch!(options, :mapper)
    display_options = Map.take(options, [:prefer, :compound_locale]) |> Map.to_list()

    locales
    |> Enum.map(&display_name(&1, locale, display_options))
    |> collator.()
    |> Enum.map(&mapper.(&1))
  end

  defp display_name(locale, @identity, options) do
    options = Keyword.put(options, :locale, locale)
    display_name = Localize.Locale.LocaleDisplay.display_name!(locale, options)

    locale_string =
      if locale.canonical_locale_id,
        do: to_string(locale.canonical_locale_id),
        else: to_string(locale.cldr_locale_id)

    %{locale: locale_string, display_name: display_name, language_tag: locale}
  end

  defp display_name(locale, _in_locale, options) do
    display_name = Localize.Locale.LocaleDisplay.display_name!(locale, options)

    locale_string =
      if locale.canonical_locale_id,
        do: to_string(locale.canonical_locale_id),
        else: to_string(locale.cldr_locale_id)

    %{locale: locale_string, display_name: display_name, language_tag: locale}
  end
end

defimpl Phoenix.HTML.Safe, for: Localize.LanguageTag do
  def to_iodata(language_tag) do
    to_string(language_tag.canonical_locale_id || language_tag.cldr_locale_id)
  end
end
