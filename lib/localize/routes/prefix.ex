defmodule Localize.Routes.Prefix do
  @moduledoc """
  The rules of a locale prefix in a path, such as `/fr/about`, as functions of the path alone.

  An application that puts the language in the first segment of its paths reads the prefix to learn the locale, writes it to build an address in another language, and decides whether a request is answered or redirected. These functions do each with no `conn`, so `Localize.Plug.PutLocale`'s `:path_prefix` source, the locale prefix plug and live hook, a language switcher, a sitemap and canonical links all apply the same rules.

  * `split/2` reads the locale from a path and returns the path without it.

  * `path/3` returns the address of a path in a locale, adding, dropping or replacing its prefix under a URL mode.

  * `target/3` decides whether a request for a path is served, and in which locale, or redirected.

  * `localized_path/3` gives a path's address in the current locale, or another, by the settings `Localize.Plug.LocalePrefix` resolved for the request, for links in templates: `localized_path(@conn, ~p"/about")`.

  ### Prefixes

  A first segment is a prefix only when it names a supported locale exactly, ignoring case and taking `_` for `-`: `/fr/about` and `/zh-hant/about` name `fr` and `zh-Hant`, while `/fr-ca/about` is not French where only `fr` is supported, and a page slug is never read as a language by closeness. A prefix is written as the supported locale it names, in lower case: `zh-Hant` is written `/zh-hant`.

  ### URL modes

  * `:prefix_others`, the default, gives the default locale no prefix: `/about` is the default locale's address and `/fr/about` the French one.

  * `:prefix_all` gives every locale a prefix, the default locale's included.

  """

  alias Localize.AcceptLanguage

  require Logger

  @modes [:prefix_others, :prefix_all]
  @default_mode :prefix_others

  @typedoc "A URL mode, as the module documentation describes it."
  @type mode :: :prefix_others | :prefix_all

  @typedoc "A locale: an identifier string or atom, or a validated language tag."
  @type locale :: String.t() | atom() | Localize.LanguageTag.t()

  @typedoc """
  A test of whether a page exists in a locale: a function of two arguments, or a `{Module, function}` or `{Module, function, args}` tuple whose function takes them before `args`.
  """
  @type exists ::
          (String.t(), Localize.LanguageTag.t() -> boolean())
          | {module(), atom()}
          | {module(), atom(), list()}

  @typedoc """
  Where `localized_path/3` finds the URL mode, the default locale and the supported locales: a `t:Plug.Conn.t/0` that `Localize.Plug.LocalePrefix` has run on, a LiveView socket the live hook has run on, or a map with `:mode`, `:default` and `:supported`, as `Localize.Plug.LocalePrefix.get_settings/1` returns it.
  """
  @type settings_source :: Plug.Conn.t() | struct() | map()

  @typedoc "What `target/3` decides for a request."
  @type target :: {:serve, Localize.LanguageTag.t()} | {:redirect, String.t(), 301 | 302}

  @doc """
  Reads the locale prefix of a path.

  ### Arguments

  * `path` is a path beginning with `/`, such as `"/fr/about"`. A query string or fragment is kept with the rest of the path.

  * `supported` is the list of locales a prefix may name, each an identifier string or atom or a `t:Localize.LanguageTag.t/0`, or `nil` for the locales configured for Localize. The default is `nil`.

  ### Returns

  * `{:ok, {locale, rest}}` when the first segment names a supported locale, where `locale` is that locale as a `t:Localize.LanguageTag.t/0` and `rest` is the path without the prefix, beginning with `/`, or

  * `{:ok, {nil, path}}` when it names none, or

  * `{:error, exception}` when `path` is not a string beginning with `/` or `supported` is not a list.

  ### Examples

      iex> {:ok, {locale, rest}} = Localize.Routes.Prefix.split("/fr/about?page=2", ["en", "fr"])
      iex> {locale.cldr_locale_id, rest}
      {:fr, "/about?page=2"}

      iex> Localize.Routes.Prefix.split("/fr-ca/about", ["en", "fr"])
      {:ok, {nil, "/fr-ca/about"}}

  """
  @spec split(String.t(), [locale()] | nil) ::
          {:ok, {Localize.LanguageTag.t() | nil, String.t()}} | {:error, Exception.t()}
  def split(path, supported \\ nil)

  def split(path, supported) when is_list(supported) or is_nil(supported) do
    case split_entry(path, entries(supported)) do
      {:ok, {nil, _rest}} ->
        {:ok, {nil, path}}

      {:ok, {entry, rest}} ->
        with {:ok, locale} <- entry_locale(entry) do
          {:ok, {locale, rest}}
        end

      {:error, _exception} = error ->
        error
    end
  end

  def split(_path, supported) do
    {:error, invalid_supported(supported)}
  end

  @doc """
  Returns the address of a path in a locale.

  Any locale prefix the path has is dropped first, so a path in one language gives its address in another.

  ### Arguments

  * `path` is a path beginning with `/`, with or without a locale prefix.

  * `locale` is the locale of the address. It is matched against the supported locales as `Localize.Plug.PutLocale` matches a locale, so `fr-CA` gives the `fr` address where only `fr` is supported.

  * `options` is a keyword list of options.

  ### Options

  * `:mode` is the URL mode, `:prefix_others` or `:prefix_all`. The default is `:prefix_others`.

  * `:default` is the default locale, which has no prefix under `:prefix_others`. The default is `Localize.default_locale/0`.

  * `:supported` is the list of supported locales, as `split/2` takes it. The default is the locales configured for Localize.

  ### Returns

  * `{:ok, path}`, or

  * `{:error, exception}` when `path` is not a string beginning with `/`, an option is not valid, or `locale` or `:default` matches no supported locale.

  ### Examples

      iex> Localize.Routes.Prefix.path("/about", :fr, default: :en, supported: ["en", "fr"])
      {:ok, "/fr/about"}

      iex> Localize.Routes.Prefix.path("/fr/about", :en, default: :en, supported: ["en", "fr"])
      {:ok, "/about"}

      iex> Localize.Routes.Prefix.path("/fr/about", :en,
      ...>   mode: :prefix_all,
      ...>   default: :en,
      ...>   supported: ["en", "fr"]
      ...> )
      {:ok, "/en/about"}

  """
  @spec path(String.t(), locale(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def path(path, locale, options \\ [])

  def path(path, locale, options) when is_list(options) do
    with {:ok, mode} <- mode(options),
         {:ok, supported} <- supported(options),
         {:ok, {_locale, rest}} <- split(path, supported),
         {:ok, prefix} <- prefix(locale, supported),
         {:ok, default_prefix} <- default_prefix(mode, options, supported) do
      {:ok, join(prefix, default_prefix, rest)}
    end
  end

  def path(_path, _locale, options) do
    {:error,
     Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")}
  end

  @doc """
  Decides whether a request for a path is served, and in which locale, or redirected.

  The decision is made from the path and the URL mode, so it is the same on a request and on a live navigation:

  * A path with a prefix is served in the locale it names, except that under `:prefix_others` a prefix naming the default locale is redirected with a `301` to the path without it, the default locale's one address.

  * A path with no prefix is, under `:prefix_others`, served in the default locale. Under `:prefix_all` it is redirected with a `302` to its address in the visitor's locale, or in the default locale when the visitor's locale is not supported or `:exists?` says the page does not exist in it.

  A `301` depends on the address alone and may be cached. A `302` depends on the visitor, so its response must vary on what the visitor's locale was found from, which is the caller's to set.

  ### Arguments

  * `path` is the requested path, beginning with `/`. A query string is kept on a redirect.

  * `locale` is the visitor's locale, as `Localize.Plug.PutLocale` found it from the session, `accept-language` or its other sources. It is used only to redirect a path with no prefix under `:prefix_all`.

  * `options` is a keyword list of options.

  ### Options

  * `:mode`, `:default` and `:supported` are as `path/3` takes them.

  * `:exists?` is a test of whether the page exists in the visitor's locale, called with the path without its prefix and the locale as a `t:Localize.LanguageTag.t/0`, for an application whose pages are data, such as a CMS page with no edition in every language. Anything but `true` is taken as `false`. The default is none: every page exists in every locale.

  ### Returns

  * `{:serve, locale}`, where `locale` is the supported locale to serve the page in, or

  * `{:redirect, path, status}`, where `status` is `301` or `302`, or

  * `{:error, exception}` when `path` is not a string beginning with `/`, an option is not valid, or `:default` matches no supported locale.

  ### Examples

      iex> Localize.Routes.Prefix.target("/en/about?page=2", :fr, default: :en, supported: ["en", "fr"])
      {:redirect, "/about?page=2", 301}

      iex> Localize.Routes.Prefix.target("/about", "fr-CA",
      ...>   mode: :prefix_all,
      ...>   default: :en,
      ...>   supported: ["en", "fr"]
      ...> )
      {:redirect, "/fr/about", 302}

      iex> {:serve, locale} =
      ...>   Localize.Routes.Prefix.target("/fr/about", :en, default: :en, supported: ["en", "fr"])
      iex> locale.cldr_locale_id
      :fr

  """
  @spec target(String.t(), locale() | nil, Keyword.t()) :: target() | {:error, Exception.t()}
  def target(path, locale, options \\ [])

  def target(path, locale, options) when is_list(options) do
    with {:ok, mode} <- mode(options),
         {:ok, supported} <- supported(options),
         {:ok, exists} <- exists_option(options),
         entries = entries(supported),
         {:ok, default} <-
           match_entry(Keyword.get(options, :default, Localize.default_locale()), entries),
         {:ok, {entry, rest}} <- split_entry(path, entries) do
      decide(mode, entry, %{
        rest: rest,
        locale: locale,
        default: default,
        entries: entries,
        exists: exists
      })
    end
  end

  def target(_path, _locale, options) do
    {:error,
     Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")}
  end

  @doc """
  Returns a path's address in a locale, by the settings resolved for a request.

  It composes a verified route with `path/3`, so `~p"/about"` is checked at compile time and given the locale's prefix at runtime. The URL mode, the default locale and the supported locales are those `Localize.Plug.LocalePrefix` resolved for the request, so a site whose settings are functions of the request needs none of them here. A path that begins with the request's script name, as a verified route in a mounted application does, keeps it in front of the prefix: `/app/about` in French is `/app/fr/about`.

  It is meant for templates, so it returns a string: a path it cannot localize is logged and returned as it is, which under either mode is still an address the plug answers. `path/3` returns `{:error, exception}` instead.

  ### Arguments

  * `source` is a `t:Plug.Conn.t/0` that `Localize.Plug.LocalePrefix` has run on, a LiveView socket the live hook has run on, or a map with `:mode`, `:default` and `:supported`.

  * `path` is a path beginning with `/`, with or without a locale prefix, such as a verified route.

  * `locale` is the locale of the address. The default is the request's locale: the one `Localize.Plug.PutLocale` set on a `conn`, and otherwise `Localize.get_locale/0`.

  ### Returns

  * The address, or `path` unchanged when it cannot be localized, or `""` when `path` is not a string.

  ### Examples

      iex> settings = %{mode: :prefix_others, default: "en", supported: ["en", "fr"]}
      iex> Localize.Routes.Prefix.localized_path(settings, "/about?page=2", :fr)
      "/fr/about?page=2"
      iex> Localize.Routes.Prefix.localized_path(settings, "/fr/about", :en)
      "/about"

  """
  @spec localized_path(settings_source(), String.t(), locale() | nil) :: String.t()
  def localized_path(source, path, locale \\ nil)

  def localized_path(source, path, locale) when is_binary(path) do
    case build_localized_path(source, path, locale) do
      {:ok, localized} ->
        localized

      {:error, exception} ->
        Logger.warning(
          "Localize.Routes.Prefix.localized_path/3: #{Exception.message(exception)}. " <>
            "#{inspect(path)} is returned as it is."
        )

        path
    end
  end

  def localized_path(_source, path, _locale) do
    Logger.warning(
      "Localize.Routes.Prefix.localized_path/3: #{inspect(path)} is not a path. \"\" is returned."
    )

    ""
  end

  defp build_localized_path(source, path, locale) do
    with {:ok, settings} <- source_settings(source) do
      {script, relative} = __split_script__(path, source)

      options = [
        mode: Map.get(settings, :mode, @default_mode),
        default: Map.get(settings, :default, Localize.default_locale()),
        supported: Map.get(settings, :supported)
      ]

      with {:ok, localized} <- path(relative, locale || source_locale(source), options) do
        {:ok, script <> localized}
      end
    end
  end

  defp source_settings(%Plug.Conn{} = conn) do
    conn
    |> Localize.Plug.LocalePrefix.get_settings()
    |> settings_found()
  end

  defp source_settings(%{__struct__: Phoenix.LiveView.Socket, private: private}) do
    private
    |> Map.get(:localize_locale_prefix)
    |> settings_found()
  end

  defp source_settings(%{__struct__: _struct} = source) do
    {:error, invalid_source(source)}
  end

  defp source_settings(%{} = settings) do
    {:ok, settings}
  end

  defp source_settings(source) do
    {:error, invalid_source(source)}
  end

  defp invalid_source(source) do
    Localize.InvalidValueError.exception(
      value: source,
      expected: "a Plug.Conn, a LiveView socket or a map of settings"
    )
  end

  defp settings_found(nil) do
    {:error,
     Localize.InvalidValueError.exception(
       value: nil,
       expected:
         "the settings of Localize.Plug.LocalePrefix or the live hook, which has not run for this request"
     )}
  end

  defp settings_found(settings) do
    {:ok, settings}
  end

  defp source_locale(%Plug.Conn{} = conn) do
    Localize.Plug.PutLocale.get_locale(conn) || Localize.get_locale()
  end

  defp source_locale(_source) do
    Localize.get_locale()
  end

  @doc false
  # A path split into the script name a verified route puts in front of it
  # in a mounted application, and the rest. `Localize.Live.LocalePrefix`
  # splits the URI of a navigation the same way.
  def __split_script__(path, source) do
    split_script(path, script_prefix(source))
  end

  # The script name a verified route puts in front of a path in a mounted
  # application.
  defp script_prefix(%Plug.Conn{script_name: script_name}) do
    Enum.map_join(script_name, &("/" <> &1))
  end

  defp script_prefix(%{__struct__: Phoenix.LiveView.Socket, endpoint: endpoint})
       when is_atom(endpoint) and not is_nil(endpoint) do
    if Code.ensure_loaded?(endpoint) and function_exported?(endpoint, :script_name, 0) do
      Enum.map_join(endpoint.script_name(), &("/" <> &1))
    else
      ""
    end
  end

  defp script_prefix(_source) do
    ""
  end

  # A path that begins with the script name keeps it in front; any other is
  # localized as it is.
  defp split_script(path, "") do
    {"", path}
  end

  defp split_script(script, script) do
    {script, "/"}
  end

  defp split_script(path, script) do
    if String.starts_with?(path, script) do
      rest = binary_part(path, byte_size(script), byte_size(path) - byte_size(script))
      split_script_rest(path, script, rest)
    else
      {"", path}
    end
  end

  defp split_script_rest(path, script, rest) do
    if String.starts_with?(rest, ["/", "?", "#"]) do
      {script, absolute(rest)}
    else
      {"", path}
    end
  end

  defp decide(:prefix_others, nil, context) do
    serve(context.default)
  end

  defp decide(:prefix_others, entry, context) do
    if normalise(entry) == normalise(context.default) do
      {:redirect, context.rest, 301}
    else
      serve(entry)
    end
  end

  defp decide(:prefix_all, nil, context) do
    entry = visitor_entry(context)

    with {:ok, locale} <- entry_locale(entry) do
      chosen = chosen_entry(entry, locale, context)
      {:redirect, join(normalise(chosen), nil, context.rest), 302}
    end
  end

  defp decide(:prefix_all, entry, _context) do
    serve(entry)
  end

  defp serve(entry) do
    with {:ok, locale} <- entry_locale(entry) do
      {:serve, locale}
    end
  end

  # The visitor's locale among the supported ones, or the default locale
  # when it matches none, as for a crawler with no session and no
  # `accept-language`.
  defp visitor_entry(context) do
    case match_entry(context.locale, context.entries) do
      {:ok, entry} -> entry
      {:error, _no_match} -> context.default
    end
  end

  defp chosen_entry(entry, locale, context) do
    if exists?(context.exists, context.rest, locale) do
      entry
    else
      context.default
    end
  end

  defp exists?(nil, _rest, _locale) do
    true
  end

  defp exists?(test, rest, locale) when is_function(test, 2) do
    test.(rest, locale) == true
  end

  defp exists?({module, function}, rest, locale) do
    apply(module, function, [rest, locale]) == true
  end

  defp exists?({module, function, args}, rest, locale) do
    apply(module, function, [rest, locale | args]) == true
  end

  defp exists_option(options) do
    exists = Keyword.get(options, :exists?)

    if valid_exists?(exists) do
      {:ok, exists}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: exists,
         expected:
           "a function of two arguments, or a {Module, function} or {Module, function, args} tuple, for the :exists? option"
       )}
    end
  end

  defp valid_exists?(nil) do
    true
  end

  defp valid_exists?(test) when is_function(test, 2) do
    true
  end

  defp valid_exists?({module, function}) when is_atom(module) and is_atom(function) do
    true
  end

  defp valid_exists?({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    true
  end

  defp valid_exists?(_exists) do
    false
  end

  # The supported entry the first segment of a path names, and the path
  # without it.
  defp split_entry("/" <> relative = path, entries) do
    {segment, tail} = first_segment(relative)
    entry = find_entry(normalise(segment), entries)

    if is_nil(entry) do
      {:ok, {nil, path}}
    else
      {:ok, {entry, absolute(tail)}}
    end
  end

  defp split_entry(path, _entries) do
    {:error, invalid_path(path)}
  end

  # The first segment of a path with its leading `/` removed, and what
  # follows it: the rest of the path, a query string or a fragment.
  defp first_segment(relative) do
    case :binary.match(relative, ["/", "?", "#"]) do
      {position, _length} ->
        {binary_part(relative, 0, position),
         binary_part(relative, position, byte_size(relative) - position)}

      :nomatch ->
        {relative, ""}
    end
  end

  defp absolute("/" <> _path = path) do
    path
  end

  defp absolute(tail) do
    "/" <> tail
  end

  # The supported entry a normalised segment names exactly.
  defp find_entry(nil, _entries) do
    nil
  end

  defp find_entry("", _entries) do
    nil
  end

  defp find_entry(key, entries) do
    Enum.find(entries, &(normalise(&1) == key))
  end

  # The supported locales, keeping only entries of a shape that names a
  # locale, so an entry from an application's own list never reaches a
  # string operation it cannot take.
  defp entries(nil) do
    Localize.supported_locales()
  end

  defp entries(supported) do
    Enum.reject(supported, &is_nil(normalise(&1)))
  end

  defp entry_locale(%Localize.LanguageTag{cldr_locale_id: locale_id} = locale)
       when not is_nil(locale_id) do
    {:ok, locale}
  end

  defp entry_locale(entry) do
    Localize.validate_locale(entry)
  end

  # The prefix of a locale, in lower case.
  defp prefix(locale, supported) do
    with {:ok, entry} <- match_entry(locale, entries(supported)) do
      {:ok, normalise(entry)}
    end
  end

  # The supported entry a locale names exactly, or else the one it matches.
  defp match_entry(locale, entries) do
    entry = find_entry(normalise(locale), entries)

    if is_nil(entry) do
      AcceptLanguage.supported_entry(locale, entries)
    else
      {:ok, entry}
    end
  end

  defp default_prefix(:prefix_all, _options, _supported) do
    {:ok, nil}
  end

  defp default_prefix(:prefix_others, options, supported) do
    options
    |> Keyword.get(:default, Localize.default_locale())
    |> prefix(supported)
  end

  # The default locale has no prefix under `:prefix_others`, so its address
  # is the path without one. `/` in French is `/fr`, not `/fr/`.
  defp join(prefix, prefix, rest) do
    rest
  end

  defp join(prefix, _default_prefix, "/" <> tail) do
    if tail == "" or String.starts_with?(tail, ["?", "#"]) do
      "/" <> prefix <> tail
    else
      "/" <> prefix <> "/" <> tail
    end
  end

  defp normalise(%Localize.LanguageTag{} = locale) do
    locale
    |> Localize.LanguageTag.to_string()
    |> normalise()
  end

  defp normalise(locale) when is_atom(locale) and not is_nil(locale) do
    locale
    |> Atom.to_string()
    |> normalise()
  end

  defp normalise(locale) when is_binary(locale) do
    locale
    |> String.downcase()
    |> String.replace("_", "-")
  end

  defp normalise(_locale) do
    nil
  end

  defp mode(options) do
    mode = Keyword.get(options, :mode, @default_mode)

    if mode in @modes do
      {:ok, mode}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: mode,
         expected: "one of #{inspect(@modes)} for the :mode option"
       )}
    end
  end

  defp supported(options) do
    supported = Keyword.get(options, :supported)

    if is_list(supported) or is_nil(supported) do
      {:ok, supported}
    else
      {:error, invalid_supported(supported)}
    end
  end

  defp invalid_path(path) do
    Localize.InvalidValueError.exception(value: path, expected: "a path beginning with /")
  end

  defp invalid_supported(supported) do
    Localize.InvalidValueError.exception(
      value: supported,
      expected: "a list of locales for the supported locales"
    )
  end
end
