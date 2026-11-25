defmodule Localize.HTML.LanguageSwitcher do
  @moduledoc """
  A language switcher: links to the same page in each of its languages.

  `links/2` takes the map of locale to URL that `Localize.HTML.Hreflang.links/2` takes and returns one entry for each language, with its name written in that language and cased for a menu, "Français" or "العربية", its `lang` and `dir`, and whether it is the page's current language. An application with markup of its own renders the entries; `language_switcher/1` renders them as a `<nav>` of links.

  Each name is written in its own language, so a reader finds their language whatever language the page is in, and each link carries that language's `lang` and `dir`, so a screen reader reads it in the right voice and Arabic or Persian runs right to left. The names come from the locale's own data, so each locale should be one Localize is configured for; a locale whose data is not installed is named in the default locale's language.

  ### Examples

      iex> {:ok, entries} =
      ...>   Localize.HTML.LanguageSwitcher.links(
      ...>     %{"en" => "/en/about", "fr" => "/fr/a-propos", "x-default" => "/about"},
      ...>     current: :fr
      ...>   )
      iex> Enum.map(entries, &{&1.name, &1.current?})
      [{"English", false}, {"Français", true}]

  """

  alias Localize.HTML.{Document, Options}

  require Logger

  @x_default "x-default"

  @typedoc "One language of a page, as `links/2` returns it."
  @type entry :: %{
          locale: String.t(),
          url: String.t(),
          name: String.t(),
          lang: String.t(),
          dir: String.t(),
          current?: boolean()
        }

  @doc """
  Returns an entry for each language of a page.

  ### Arguments

  * `urls` is a map of locale to the page's URL in that locale. A locale is any term `Localize.validate_locale/1` accepts. The key `"x-default"`, which `Localize.HTML.Hreflang.links/2` takes for the fallback page, names no language and is left out.

  * `options` is a keyword list of options.

  ### Options

  * `:current` is the locale the page is in. The entry it matches, as `Localize.Plug.PutLocale` matches a locale against the supported ones, is the current one, so `fr-CA` marks `fr`. The default is `Localize.get_locale/0`.

  ### Returns

  * `{:ok, entries}`, sorted by name in the collation of the current locale, each a map with `:locale` (the canonical BCP 47 tag), `:url`, `:name` (the language's name in itself, cased for a menu), `:lang`, `:dir` (`"ltr"` or `"rtl"`) and `:current?`, or

  * `{:error, exception}` when `urls` is not a map, a locale in it is not valid, a URL is not a string, or `:current` is not a valid locale.

  ### Examples

      iex> {:ok, [arabic]} = Localize.HTML.LanguageSwitcher.links(%{"ar" => "/ar"}, current: :en)
      iex> {arabic.lang, arabic.dir, arabic.current?}
      {"ar", "rtl", false}

  """
  @spec links(map(), Keyword.t()) :: {:ok, [entry()]} | {:error, Exception.t()}
  def links(urls, options \\ [])

  def links(urls, options) when is_map(urls) and is_list(options) do
    with {:ok, current} <-
           Localize.validate_locale(Keyword.get(options, :current, Localize.get_locale())),
         {:ok, entries} <- entries(urls) do
      {:ok, entries |> mark_current(current) |> Options.collate(& &1.name, current)}
    end
  end

  def links(urls, options) when is_list(options) do
    {:error,
     Localize.InvalidValueError.exception(value: urls, expected: "a map of locale to URL")}
  end

  def links(_urls, options) do
    {:error,
     Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")}
  end

  defp entries(urls) do
    urls
    |> Enum.reject(fn {locale, _url} -> to_string_or_nil(locale) == @x_default end)
    |> Enum.reduce_while({:ok, []}, &add_entry/2)
  end

  defp add_entry({locale, url}, {:ok, entries}) do
    case entry(locale, url) do
      {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
      {:error, _exception} = error -> {:halt, error}
    end
  end

  defp entry(_locale, url) when not is_binary(url) do
    {:error, Localize.InvalidValueError.exception(value: url, expected: "a URL string")}
  end

  defp entry(locale, url) do
    with {:ok, tag} <- Localize.validate_locale(locale),
         {:ok, [lang: lang, dir: dir]} <- Document.attributes(tag) do
      {:ok,
       %{locale: lang, url: url, name: own_name(tag, lang), lang: lang, dir: dir, current?: false}}
    end
  end

  # The language's name in itself, cased for a menu, or its tag where it
  # has no name.
  defp own_name(tag, lang) do
    case Localize.Locale.LocaleDisplay.display_name(tag,
           locale: tag,
           capitalization: :ui_list_or_menu
         ) do
      {:ok, name} -> name
      {:error, _exception} -> lang
    end
  end

  # The entry the current locale matches, by the test the plugs apply to a
  # locale in a request, is the current one.
  defp mark_current(entries, current) do
    supported = Enum.map(entries, & &1.lang)

    case Localize.AcceptLanguage.supported_match(current, supported) do
      {:ok, matched} ->
        Enum.map(entries, &%{&1 | current?: &1.lang == to_string(matched.canonical_locale_id)})

      {:error, _no_match} ->
        entries
    end
  end

  defp to_string_or_nil(locale) when is_binary(locale) or is_atom(locale) do
    to_string(locale)
  end

  defp to_string_or_nil(_locale) do
    nil
  end

  if Code.ensure_loaded?(Phoenix.Component) do
    use Phoenix.Component

    @doc """
    Renders a language switcher: a `<nav>` holding a list of links to the page in each of its languages.

    Each link carries `hreflang`, `lang` and `dir`, and the current language's carries `aria-current="page"`. Entries that are not valid are logged and nothing is rendered, so a page still renders.

    ### Attributes

    * `:urls` is the map of locale to URL that `links/2` takes. Required.

    * `:current` is the locale the page is in. The default is `Localize.get_locale/0`.

    * `:navigate` is `true` to link with `navigate`, a live navigation within one live session, and `false` (the default) to link with `href`.

    * `:label` is the `aria-label` of the `<nav>`, in the page's language, such as `"Language"`. The default is none.

    * Any other attribute, such as `class`, is rendered on the `<nav>`.

    ### Examples

        <Localize.HTML.LanguageSwitcher.language_switcher
          urls={%{"en" => ~p"/en/about", "fr" => ~p"/fr/a-propos"}}
          current={@locale}
          label="Language"
        />

    """
    attr(:urls, :map, required: true, doc: "A map of locale to the page's URL in that locale.")
    attr(:current, :any, default: nil, doc: "The page's locale; the current locale by default.")
    attr(:navigate, :boolean, default: false, doc: "Link with `navigate` rather than `href`.")
    attr(:label, :string, default: nil, doc: "The `aria-label` of the `<nav>`.")
    attr(:rest, :global)

    @spec language_switcher(map()) :: Phoenix.LiveView.Rendered.t()
    def language_switcher(assigns) do
      case links(assigns.urls, current: assigns.current || Localize.get_locale()) do
        {:ok, entries} ->
          assigns = assign(assigns, :entries, entries)

          ~H"""
          <nav aria-label={@label} {@rest}>
            <ul>
              <li :for={entry <- @entries}>
                <.link
                  {link_target(entry.url, @navigate)}
                  hreflang={entry.lang}
                  lang={entry.lang}
                  dir={entry.dir}
                  aria-current={entry.current? && "page"}
                >
                  {entry.name}
                </.link>
              </li>
            </ul>
          </nav>
          """

        {:error, exception} ->
          Logger.warning(
            "Localize.HTML.LanguageSwitcher.language_switcher/1: #{Exception.message(exception)}. " <>
              "No language switcher is rendered."
          )

          ~H""
      end
    end

    defp link_target(url, true) do
      %{navigate: url}
    end

    defp link_target(url, false) do
      %{href: url}
    end
  end
end
