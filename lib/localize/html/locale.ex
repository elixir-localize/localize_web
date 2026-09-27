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

  alias Localize.HTML.Options

  @identity :identity

  @omit_from_select_options [
    :locales,
    :locale,
    :mapper,
    :collator,
    :add_likely_subtags,
    :prefer,
    :compound_locale
  ]

  @dont_include_default [:"en-001", :root, :und]

  @doc """
  Generates an HTML select tag for a locale list that can be used with a `Phoenix.HTML.Form.t`.

  ### Arguments

  * `form` is a `t:Phoenix.HTML.Form.t/0` form.

  * `field` is a `t:Phoenix.HTML.Form.field/0` field.

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  * `:locales` defines the list of locales to be displayed in the select tag. The default is `Localize.all_locale_ids/0` with meta locales excluded.

  * `:locale` defines the locale used to localise the display names. The default is the locale returned by `Localize.get_locale/0`. If set to `:identity` then each locale in `:locales` will be rendered in its own locale.

  * `:collator` is a function used to sort the locales. The default collator sorts by display name.

  * `:mapper` is a function that creates the text to be displayed in the select tag for each locale. It receives a map with `:display_name`, `:locale` and `:language_tag` keys. The default mapper is `&{&1.display_name, &1.locale}`.

  * `:selected` identifies the locale to be selected by default in the select tag. The default is `nil`.

  * `:prompt` is a prompt displayed at the top of the select box.

  ### Returns

  * A `t:Phoenix.HTML.safe/0` select tag, or

  * `{:error, exception}` when an option is invalid.

  ### Examples

      iex> Localize.HTML.Locale.select(:my_form, :locale_list, selected: "en")

  """
  @spec select(
          form :: Phoenix.HTML.Form.t(),
          field :: Phoenix.HTML.Form.field(),
          select_options
        ) ::
          Phoenix.HTML.safe() | {:error, Exception.t()}

  def select(form, field, options \\ []) do
    case validate_options(options) do
      {:ok, %{locale: locale} = options} ->
        select_options =
          options
          |> Map.drop(@omit_from_select_options)
          |> Map.to_list()

        options = build_locale_options(options)
        {options, select_options} = add_lang_attribute(locale, options, select_options)

        PhoenixHTMLHelpers.Form.select(form, field, options, select_options)

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Generates a list of options for a locale list that can be used with `Phoenix.HTML.Form.options_for_select/2` or to create a `<datalist>`.

  ### Arguments

  * `options` is a `t:Keyword.t/0` list of options.

  ### Options

  See `Localize.HTML.Locale.select/3` for options.

  ### Returns

  * A list of `{display_name, locale_string}` tuples, or

  * `{:error, exception}` when an option is invalid.

  """
  @spec locale_options(select_options) :: list(tuple()) | {:error, Exception.t()}

  def locale_options(options \\ []) do
    with {:ok, options} <- validate_options(options) do
      build_locale_options(options)
    end
  end

  defp add_lang_attribute(@identity, options, select_options) do
    options = Enum.map(options, fn {key, value} -> [key: key, value: value, lang: value] end)
    {options, select_options}
  end

  defp add_lang_attribute(locale, options, select_options) do
    {options, Keyword.put(select_options, :lang, locale)}
  end

  defp validate_options(options) do
    with {:ok, options} <- Options.merge(options, default_options()),
         {:ok, options} <- validate_display_locale(options),
         {:ok, options} <- Options.function(options, :collator),
         {:ok, options} <- Options.function(options, :mapper),
         {:ok, options} <- Options.optional(options, :selected, &validate_locale/1),
         {:ok, options} <- default_locales(options) do
      Options.list(options, :locales, &validate_locale/1)
    end
  end

  defp default_options do
    %{
      locales: nil,
      locale: Localize.get_locale(),
      collator: &default_collator/1,
      mapper: &{&1.display_name, &1.locale},
      selected: nil,
      add_likely_subtags: false,
      compound_locale: false,
      prefer: :default
    }
  end

  defp default_collator(locales) do
    Enum.sort(locales, &(&1.display_name < &2.display_name))
  end

  # `:identity` renders each locale in itself; any other value is the
  # locale the display names are rendered in.
  defp validate_display_locale(%{locale: @identity} = options), do: {:ok, options}
  defp validate_display_locale(options), do: Options.locale(options)

  defp default_locales(%{locales: nil} = options) do
    {:ok, Map.put(options, :locales, Localize.all_locale_ids() -- @dont_include_default)}
  end

  defp default_locales(options), do: {:ok, options}

  # `Localize.validate_locale/1` returns an error for any term that is not
  # a locale, so no type check is needed first.
  defp validate_locale(locale), do: Localize.validate_locale(locale)

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
    display_name(locale, locale, options)
  end

  # CLDR has no display name for a few locales (`apc`, `skr` and others in
  # English), so the locale code stands in for the name.
  defp display_name(locale, in_locale, options) do
    locale_string =
      if locale.canonical_locale_id,
        do: to_string(locale.canonical_locale_id),
        else: to_string(locale.cldr_locale_id)

    display_name =
      case Localize.Locale.LocaleDisplay.display_name(
             locale,
             Keyword.put(options, :locale, in_locale)
           ) do
        {:ok, name} -> name
        {:error, _exception} -> locale_string
      end

    %{locale: locale_string, display_name: display_name, language_tag: locale}
  end
end

defimpl Phoenix.HTML.Safe, for: Localize.LanguageTag do
  def to_iodata(language_tag) do
    to_string(language_tag.canonical_locale_id || language_tag.cldr_locale_id)
  end
end
