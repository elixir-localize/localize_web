defmodule Localize.Plug.PutLocale do
  @private_key :localize_locale
  @source_key :localize_locale_source
  @session_key_private :localize_session_key
  @settings_private :localize_put_locale_settings
  @session_key "localize_locale"

  @default_from [:route, :path, :query, :session, :accept_language]
  @default_param_name "locale"

  @moduledoc """
  Plug that discovers and sets the locale for the current process.

  The locale can be derived from the accept-language header, a query parameter, a URL parameter, a body parameter, a cookie, the route, the session, or the hostname TLD. Sources are checked in the order specified by the `:from` option, and the first successful match wins.

  A source counts only when what it holds matches a locale the application supports. An identifier that is valid but matches none, such as `pt` where Portuguese is not supported, is passed over and the next source is checked. The same holds for the locale of a host's territory. The supported locales are those configured for Localize, or the list given with the `:supported` option, for an application whose locales are known only at runtime.

  When a locale is found, `Localize.put_locale/1` is always called to set the process locale. If Gettext backends are configured, the locale is also set on each backend.

  If a locale is found then `conn.private[:localize_locale]` is also set. It can be retrieved with `Localize.Plug.PutLocale.get_locale/1`. The source that decided it is recorded too, and `Localize.Plug.PutLocale.get_locale_source/1` returns it.

  The response gets a `vary` header for each request header the plug read to find the locale: `accept-language` for `:accept_language`, and `cookie` for `:session` and `:cookie`. A source read before the one that decided counts too, because a value there would have changed the locale. The plug adds them in a `vary` line of its own, and leaves any `vary` line already on the response as it is. The header tells a shared cache which requests a stored response may be reused for. A `{Module, function}` source that reads a request header must add its own `vary` value. The `:vary` option turns the header off for an application that declares how its responses vary itself.

  > #### The session and shared caches {: .warning}
  >
  > The default `:from` list reads the session, so the response to a request with no locale in its URL carries `vary: cookie`. A shared cache that honours `vary` can then reuse that response only for the visitor it was made for, and so works like a private cache. Some caches store no response at all that has a `vary` other than `accept-encoding`, and that applies to `vary: accept-language` too. This matters only to an application that makes its pages cacheable by a shared cache: Plug's default `cache-control` is private. Such an application does one of the following:
  >
  > * Puts the locale in the URL. It is found before the session is read, and the response carries no `vary`.
  >
  > * Leaves `:session` out of `:from`. A locale stored in the session is then no longer read, and the response carries `vary: accept-language` when that header is read.
  >
  > * For a cache inside the application alone, copies the session's locale into a request header before the cache, sends a `vary` that names that header, and sets `vary: false`.
  >
  > With `:session` still in `:from`, `vary: false` on its own lets a cache in front of the application serve one visitor's language to another.
  >
  > See [the `vary` response header](guides/http-locale-discovery.md#the-vary-response-header) in the HTTP locale discovery guide.

  ### Options

  * `:from` is a list specifying where in the request to look for the locale. The default is `#{inspect(@default_from)}`: a locale in the URL is an explicit choice, so it wins over the session, which in turn wins over the browser's `accept-language` header. The valid options are:

    * `:accept_language` will parse the `accept-language` header and find the best matched configured locale.

    * `:path` will look for a locale by examining `conn.path_params`.

    * `:path_prefix` will take the first segment of the path, `conn.path_info`, when it names a supported locale, ignoring case and taking `_` for `-`: `/fr/about` and `/zh-hant/about` name `fr` and `zh-Hant`. It is for addresses whose language prefix is optional, such as `/about` in the primary language beside `/fr/about`, which a `/:locale` scope cannot route, and for catch-all routes. The segment must name a supported locale exactly, so `/fr-ca/about` is not French where only `fr` is supported, and a page slug is never read as a language by closeness. The segment stays in the path for the router.

    * `:query` will look for a locale by examining `conn.query_params`.

    * `:body` will look for a locale by examining `conn.body_params`.

    * `:cookie` will look for a locale in the request cookie(s). Cookies must
      be fetched before this plug runs. In Phoenix browser pipelines,
      `fetch_session/1` fetches cookies as part of loading the session.

    * `:session` will look for a locale in the session. `fetch_session/1` must
      run before this plug when `:session` is used.

    * `:route` will look for a locale in the route that was matched under the key `private.#{inspect(@private_key)}`.

    * `:host` will attempt to resolve a locale from the hostname top-level domain.

    * `{Module, function, args}` in which case the indicated function will be called. If it returns `{:ok, locale}` then the locale is set. `locale` must be a `t:Localize.LanguageTag.t/0`.

    * `{Module, function}` in which case the function is called with `conn` and `options` as its two arguments.

    > #### `:session` and `:cookie` send `vary: cookie` {: .warning}
    >
    > When the plug reads `:session` or `:cookie` the response carries `vary: cookie`, and a shared cache that honours it can reuse the response only for the visitor it was made for. The default list reads the session for every request with no locale in its URL. An application with a shared cache in front of its pages leaves `:session` and `:cookie` out of this list. Setting `vary: false` with either still in the list is no substitute: the cache then serves one visitor's language to another.

  * `:default` is the default locale to set if no locale is found by other configured methods. It can be a string like `"en"` or a `Localize.LanguageTag` struct. It may also be `:none` to indicate that no locale is to be set by default. Lastly, it may also be a `{Module, function, args}` or `{Module, function}` tuple. The default is `Localize.default_locale/0` (resolved at runtime, not compile time).

  * `:gettext` is a Gettext backend module or a list of Gettext backend modules on which the locale will be set. The default is `[]` (no Gettext backends).

  * `:param` is the name of the parameter to look for in the query, path, body, or cookie. The default is `"locale"`.

  * `:supported` is the list of locales the request is matched against, for an application whose locales are known only at runtime, such as a site whose languages are kept in a database. Each entry is a locale identifier string or atom, or a `t:Localize.LanguageTag.t/0`, and should be a locale Localize is configured for, or its data falls back to another locale. It may also be a `{Module, function}` or `{Module, function, args}` tuple, whose function is called with the `conn` and the plug's options, followed by `args`, and returns the list: a function that returns anything else is logged, and no locale is taken from the request. The locale found is then the entry that matched, so `?locale=fr-CA` with `supported: ["en", "fr"]` sets `fr`, and every source is matched against the list but two, which are taken as they stand (`:path_prefix` must name an entry exactly): the tag a localized route stores, and the locale a `{Module, function}` or `{Module, function, args}` source returns. Such a source finds the list in its options under `:supported`. The `:default` locale is not matched. The default is the locales configured for Localize.

  * `:content_language` is `true` or `false`, and says whether the plug puts a `content-language` header naming the canonical BCP 47 tag of the locale it set, such as `fr-CA`, on the response. The default is `false`. The header is set when the plug runs, so a later plug can replace it; no locale set means no header.

  * `:session_key` is the session key the `:session` source reads, as a non-empty string. `Localize.Plug.PutSession` writes the locale under the same key and `Localize.Plug.live_session_locale/1` hands it to a LiveView under it; `get_session_key/1` returns it. Two pipelines with different keys keep two locales apart, such as a site's pages and its admin. The default is `"#{@session_key}"`.

  * `:vary` is `true` or `false`, and says whether the plug adds the `vary` header described above. The default is `true`. With `false` the plug adds none, and the application declares how its responses vary: for example where a cache inside the application keys on a request header the application derives from the session. A shared cache that is told nothing serves one visitor's language to another.

  ### Examples

      plug Localize.Plug.PutLocale,
        from: [:query, :path, :body, :cookie, :accept_language],
        param: "locale",
        gettext: MyApp.Gettext

      plug Localize.Plug.PutLocale,
        from: [:route, :session, :accept_language],
        gettext: [MyApp.Gettext, MyOtherApp.Gettext]

      plug Localize.Plug.PutLocale,
        from: [:route, :session, :accept_language],
        vary: false

      plug Localize.Plug.PutLocale,
        from: [:path, :session, :accept_language],
        supported: {MyApp.Sites, :locales}

  """

  import Plug.Conn
  require Logger

  @from_options [
    :accept_language,
    :path,
    :path_prefix,
    :body,
    :query,
    :session,
    :cookie,
    :host,
    :route
  ]

  @language_header "accept-language"

  # A country-code TLD is always exactly two ASCII letters. Every generic TLD
  # is longer, so a length test excludes all of them at once and keeps doing
  # so as new ones are created — more durable than a list, and necessary:
  # "com" upcases to "COM", which is the ISO alpha-3 code for Comoros and
  # validates to :KM.
  @cctld_length 2

  # Country-code TLDs sold and used as generic domains far more often than as
  # country markers. Resolving these to a territory produces a language the
  # reader is unlikely to speak — ".co" would yield Spanish, ".me" Serbian,
  # ".ly" Arabic — on domains chosen for the letters, not the country.
  #
  # A miss here is cheap: the next entry in :from is consulted. A wrong answer
  # is expensive. The doubtful cases are therefore excluded, and the list is
  # replaceable via the :generic_tlds option for a site that genuinely is
  # Colombian or Montenegrin.
  @generic_use_cctlds ~w(ai cc co fm gg io ly me nu sh st to tv ws)

  @doc false
  def init(options) do
    options
    |> validate_from(options[:from])
    |> validate_param(options[:param])
    |> validate_gettext(options[:gettext])
    |> validate_default(options[:default])
    |> validate_vary(options[:vary])
    |> validate_supported(options[:supported])
    |> validate_session_key(options[:session_key])
    |> validate_content_language(options[:content_language])
  end

  @doc false
  def call(conn, options) do
    options = Keyword.put(options, :supported, supported_locales(conn, options))
    {found, consulted} = locale_from_params(conn, options[:from], options)
    source = source(found, consulted)
    locale = found || default(conn, options)

    conn =
      conn
      |> put_vary(consulted, options[:vary])
      |> put_private(@session_key_private, options[:session_key])
      |> put_private(@settings_private, options)

    if locale do
      set_locale(conn, locale, source, options)
    else
      conn
    end
  end

  @doc false
  # The options of the `PutLocale` that ran for this request, with its
  # supported locales resolved for it, or `nil` when none ran. A plug that
  # runs after it, such as `Localize.Plug.LocalePrefix`, reads its
  # settings here rather than being given them again.
  def __settings__(%Plug.Conn{private: private}) do
    private[@settings_private]
  end

  @doc false
  # The default locale of the `PutLocale` that ran for this request, by its
  # `:default` option, or `nil` when it has none.
  def __default_locale__(conn, options) do
    default(conn, options)
  end

  @doc false
  # Replaces the locale set for this request, for a plug that decides it
  # after `PutLocale` has run: the process locale, the Gettext locales, the
  # stored locale and source, and the `content-language` header, as
  # `PutLocale` itself sets them.
  def __put_locale__(conn, locale, source) do
    set_locale(conn, locale, source, __settings__(conn) || [])
  end

  defp set_locale(conn, locale, source, options) do
    Localize.put_locale(locale)

    options
    |> Keyword.get(:gettext, [])
    |> Enum.each(&put_gettext_locale(&1, locale))

    conn
    |> put_private(@private_key, locale)
    |> put_private(@source_key, source)
    |> put_content_language(locale, Keyword.get(options, :content_language, false))
  end

  # With `content_language: true` the response names its language, the
  # canonical BCP 47 tag of the locale set for it.
  defp put_content_language(conn, _locale, false) do
    conn
  end

  defp put_content_language(conn, locale, true) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> put_resp_header(conn, "content-language", to_string(tag.canonical_locale_id))
      {:error, _exception} -> conn
    end
  end

  # The source that decided: the last one consulted when one of them had
  # a locale, and the `:default` option when none did.
  defp source(nil, _consulted) do
    :default
  end

  defp source(_locale, consulted) do
    List.last(consulted)
  end

  defp put_gettext_locale(gettext_backend, locale) do
    case Localize.Locale.gettext_locale_id(locale, gettext_backend) do
      {:ok, gettext_locale} ->
        Gettext.put_locale(gettext_backend, gettext_locale)

      {:error, _reason} ->
        Logger.warning(
          "Localize.Plug.PutLocale: locale #{inspect(locale.cldr_locale_id)} does not have " <>
            "a matching Gettext locale for backend #{inspect(gettext_backend)}. " <>
            "No Gettext locale has been set."
        )
    end
  end

  # The :__localize_default__ sentinel defers the Localize.default_locale/0
  # call from init/1 (compile time) to call/2 (request time). This avoids
  # loading the full CLDR dataset into the compiler's VM when the plug is
  # declared in a Phoenix router pipeline — a common cause of OOM errors
  # on memory-constrained build environments (Docker, CI, Fly.io).
  defp default(conn, options) do
    case options[:default] do
      :__localize_default__ -> Localize.default_locale()
      {module, function, args} -> get_default(conn, options, module, function, args)
      other -> other
    end
  end

  defp get_default(conn, options, module, function, args) do
    case apply(module, function, [conn, options | args]) do
      {:ok, %Localize.LanguageTag{} = locale} -> locale
      _other -> nil
    end
  end

  @doc """
  Returns the name of the session key used to store the locale.

  ### Returns

  * The session key, a string.

  ### Examples

      iex> Localize.Plug.PutLocale.session_key()
      "localize_locale"

  """
  def session_key do
    @session_key
  end

  @doc """
  Returns the session key `Localize.Plug.PutLocale` read for a request.

  `Localize.Plug.PutSession` writes the locale under this key and `Localize.Plug.live_session_locale/1` hands it to a LiveView under it, so the key is configured once, with the `:session_key` option of `Localize.Plug.PutLocale`.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * The session key as a string: the plug's `:session_key` option, or `session_key/0` when the plug has not run or `conn` is not a `t:Plug.Conn.t/0`.

  ### Examples

      iex> Localize.Plug.PutLocale.get_session_key(%Plug.Conn{})
      "localize_locale"

  """
  @spec get_session_key(term()) :: String.t()
  def get_session_key(%Plug.Conn{private: private}) do
    Map.get(private, @session_key_private, @session_key)
  end

  def get_session_key(_conn) do
    @session_key
  end

  @doc false
  def private_key do
    @private_key
  end

  @doc false
  # The sources the `:from` option accepts by name. `Localize.Plug.PutSession`
  # validates its own `:from` option against the same list.
  def sources do
    @from_options
  end

  @doc """
  Returns the locale set by `Localize.Plug.PutLocale`.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * A `t:Localize.LanguageTag.t/0`, or `nil` when no locale was set or `conn` is not a `t:Plug.Conn.t/0`.

  ### Examples

      iex> conn =
      ...>   Plug.Test.conn(:get, "/?locale=fr")
      ...>   |> Localize.Plug.PutLocale.call(Localize.Plug.PutLocale.init(from: [:query]))
      iex> Localize.Plug.PutLocale.get_locale(conn).cldr_locale_id
      :fr

  """
  def get_locale(%Plug.Conn{private: private}) do
    private[@private_key]
  end

  def get_locale(_conn) do
    nil
  end

  @doc """
  Returns the source that decided the locale set by `Localize.Plug.PutLocale`.

  This tells a locale the visitor chose, in the URL or a form, from one that was only inferred, from the `accept-language` header or the default. `Localize.Plug.PutSession` reads it to store the first kind and not the second.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * The entry of the `:from` option the locale was found in, such as `:query`, `:session` or `:accept_language`, or

  * `:default` when no source had a locale and the `:default` option supplied it, or

  * `nil` when no locale was set or `conn` is not a `t:Plug.Conn.t/0`.

  ### Examples

      iex> conn =
      ...>   Plug.Test.conn(:get, "/?locale=fr")
      ...>   |> Localize.Plug.PutLocale.call(Localize.Plug.PutLocale.init(from: [:query]))
      iex> Localize.Plug.PutLocale.get_locale_source(conn)
      :query

  """
  @spec get_locale_source(term()) ::
          atom() | {module(), atom()} | {module(), atom(), list()} | nil
  def get_locale_source(%Plug.Conn{private: private}) do
    private[@source_key]
  end

  def get_locale_source(_conn) do
    nil
  end

  @doc """
  Attempts to resolve a locale from a hostname's top-level domain.

  Extracts the TLD, validates it as a territory code, and returns the best
  matching locale for that territory.

  Note what this can and cannot tell you. A TLD identifies a *territory*, and
  the language is then inferred from it, so the result is only as good as that
  inference: Belgium has three official languages, Switzerland four, Canada
  two. Prefer `:host` below the sources that carry an actual language — the
  path, a cookie, the session, `accept-language` — rather than above them.

  Generic top-level domains resolve to nothing, as do country-code domains
  that are predominantly used generically. See the `:generic_tlds` option.

  Where a domain and a territory code disagree — `.uk` is the domain while
  `GB` is the code — resolution relies on `Localize.validate_territory/1`
  applying CLDR's territory aliases.

  ### Arguments

  * `host` is a hostname string (e.g., "example.co.uk").

  * `options` is a keyword list of options.

  ### Options

  * `:generic_tlds` is a list of lowercase country-code TLDs to treat as
    generic and resolve to `nil`. The default is
    `#{inspect(@generic_use_cctlds)}`. Pass a list without a given entry to
    have that domain resolve to its territory — appropriate for a site whose
    `.co` really is Colombian.

  ### Returns

  * `{:ok, Localize.LanguageTag.t()}`,

  * `{:error, reason}`, or

  * `nil` when the host has a generic top-level domain, one that is not a territory, or `host` is not a string.

  ### Examples

      iex> {:ok, locale} = Localize.Plug.PutLocale.locale_from_host("example.de")
      iex> locale.territory
      :DE

      # Generic, so no territory is inferred
      iex> Localize.Plug.PutLocale.locale_from_host("example.com")
      nil

      # A country-code domain used generically
      iex> Localize.Plug.PutLocale.locale_from_host("example.co")
      nil

      # ...unless the caller says otherwise
      iex> {:ok, locale} = Localize.Plug.PutLocale.locale_from_host("example.co", generic_tlds: [])
      iex> locale.territory
      :CO

  """
  def locale_from_host(host, options \\ [])

  def locale_from_host(nil, _options), do: nil

  def locale_from_host(host, options) when is_binary(host) do
    generic = Keyword.get(options, :generic_tlds, @generic_use_cctlds)

    tld =
      host
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    if country_code_tld?(tld) and tld not in generic, do: locale_from_tld(tld)
  end

  def locale_from_host(_host, _options), do: nil

  # A country-code domain names its territory, unless no territory has the code.
  defp locale_from_tld(tld) do
    case Localize.validate_territory(String.upcase(tld)) do
      {:ok, territory} -> Localize.validate_locale("und-#{territory}")
      {:error, _not_a_territory} -> nil
    end
  end

  defp country_code_tld?(tld) do
    String.length(tld) == @cctld_length and tld =~ ~r/^[a-z]{2}$/
  end

  # Returns the locale of the first source that has one, and the sources
  # consulted to find it (all of them when none has one).
  defp locale_from_params(conn, from, options) do
    Enum.reduce_while(from, {nil, []}, fn source, {nil, consulted} ->
      consulted = consulted ++ [source]

      case fetch_param(conn, source, options[:param], options) do
        {:ok, locale} -> {:halt, {locale, consulted}}
        _other -> {:cont, {nil, consulted}}
      end
    end)
  end

  # A shared cache must key the response on every request header that
  # could have changed the locale, or it serves one language to everyone.
  # The fields go in a `vary` line of their own: a response may carry
  # several, so the lines other plugs set are neither read nor rewritten.
  # With `vary: false` the application declares how its responses vary.
  defp put_vary(conn, _consulted, false) do
    conn
  end

  defp put_vary(conn, consulted, _vary) do
    fields =
      consulted
      |> Enum.flat_map(&vary_fields/1)
      |> Enum.uniq()

    add_vary(conn, fields)
  end

  defp add_vary(conn, []) do
    conn
  end

  defp add_vary(conn, [_ | _] = fields) do
    prepend_resp_headers(conn, [{"vary", Enum.join(fields, ", ")}])
  end

  defp vary_fields(:accept_language), do: ["accept-language"]
  defp vary_fields(source) when source in [:session, :cookie], do: ["cookie"]
  defp vary_fields(_source), do: []

  defp fetch_param(conn, :accept_language, _param, options) do
    case get_req_header(conn, @language_header) do
      [accept_language | _] ->
        Localize.AcceptLanguage.best_match(accept_language, supported: options[:supported])

      [] ->
        nil
    end
  end

  defp fetch_param(
         %Plug.Conn{query_params: %Plug.Conn.Unfetched{aspect: :query_params}} = conn,
         :query,
         param,
         options
       ) do
    conn = fetch_query_params(conn)
    fetch_param(conn, :query, param, options)
  end

  defp fetch_param(conn, :query, param, options) do
    conn
    |> Map.get(:query_params)
    |> Map.get(param)
    |> validate_locale_param(options[:supported])
  end

  defp fetch_param(conn, :path, param, options) do
    conn
    |> Map.get(:path_params)
    |> Map.get(param)
    |> validate_locale_param(options[:supported])
  end

  defp fetch_param(conn, :path_prefix, _param, options) do
    conn
    |> Map.get(:path_info)
    |> path_prefix_locale(options[:supported])
  end

  defp fetch_param(conn, :body, param, options) do
    conn
    |> Map.get(:body_params)
    |> Map.get(param)
    |> validate_locale_param(options[:supported])
  end

  defp fetch_param(conn, :session, _param, options) do
    conn
    |> get_session(options[:session_key])
    |> validate_locale_param(options[:supported])
  end

  defp fetch_param(conn, :cookie, param, options) do
    conn
    |> Map.get(:cookies)
    |> Map.get(param)
    |> validate_locale_param(options[:supported])
  end

  defp fetch_param(conn, :host, _param, options) do
    conn
    |> Map.get(:host)
    |> locale_from_host(Keyword.take(options, [:generic_tlds]))
    |> supported_host_locale(options[:supported])
  end

  defp fetch_param(conn, :route, _param, options) do
    conn
    |> Map.fetch!(:private)
    |> Map.get(@private_key)
    |> validate_locale_param(options[:supported])
  end

  defp fetch_param(conn, {module, function, args}, _param, options) do
    apply(module, function, [conn, options | args])
  end

  defp fetch_param(conn, {module, function}, _param, options) do
    apply(module, function, [conn, options])
  end

  # A path prefix is read by `Localize.Routes.Prefix.split/2`, so the plug,
  # the locale prefix plug and hook, and the addresses an application builds
  # apply one rule: the segment must name a supported locale exactly. Only
  # the first segment is passed, and it is a prefix only when nothing of it
  # is left over, so a segment an adapter has decoded to hold `?` or `#` is
  # never read as a prefix followed by a query string.
  defp path_prefix_locale([segment | _rest], supported) do
    case Localize.Routes.Prefix.split("/" <> segment, supported) do
      {:ok, {nil, _path}} -> nil
      {:ok, {locale, "/"}} -> {:ok, locale}
      {:ok, {_locale, _not_one_segment}} -> nil
      {:error, _exception} = error -> error
    end
  end

  defp path_prefix_locale(_path_info, _supported) do
    nil
  end

  # A territory's locale is a hit only when it matches a supported locale,
  # as an identifier in the request is. Without the test, a territory whose
  # language is not supported resolved to the first supported locale.
  defp supported_host_locale({:ok, locale}, supported) do
    Localize.AcceptLanguage.supported_match(locale, supported)
  end

  defp supported_host_locale(other, _supported) do
    other
  end

  defp validate_locale_param(nil, _supported) do
    nil
  end

  # The router, `Localize.Plug.AcceptLanguage` and this plug each store a tag
  # they validated, so a tag found here is trusted as it stands.
  defp validate_locale_param(%Localize.LanguageTag{cldr_locale_id: id} = locale, _supported)
       when not is_nil(id) do
    {:ok, locale}
  end

  # With a list of supported locales, an identifier is a hit when it
  # matches an entry, and the entry is the locale. The root locale is a hit
  # only when the list holds it.
  defp validate_locale_param(locale, [_ | _] = supported) do
    Localize.AcceptLanguage.supported_match(locale, supported)
  end

  defp validate_locale_param(_locale, []) do
    nil
  end

  # An identifier from the request is a hit only when it matches a locale
  # the application supports, by the test `Localize.AcceptLanguage` applies
  # to a tag in the header. `Localize.validate_locale/1` alone always
  # answers for a valid tag: with the root locale `und` for one CLDR has no
  # data for, such as `tlh`, and with the first supported locale for one
  # that is too distant from all of them, such as `pt` where only `en` and
  # `fr` are supported. Both are right for formatting and neither is what
  # the visitor asked for, so they are misses and the next source is tried.
  # The root locale is kept when it is what was asked for, as
  # `Localize.LanguageTag.best_match/3` matches a root only to the root.
  defp validate_locale_param(locale, nil) do
    with {:ok, tag} <- Localize.validate_locale(locale) do
      supported_match(tag, locale)
    end
  end

  # An identifier that is the id of the locale it resolved to names a
  # supported locale outright, and needs no scoring. That is what the
  # session holds, which is read on every request with no locale in its
  # URL. Any other identifier is scored against the locale it resolved to,
  # which takes about 15 microseconds.
  defp supported_match(%Localize.LanguageTag{cldr_locale_id: locale_id} = tag, locale)
       when is_binary(locale) do
    if Atom.to_string(locale_id) == locale do
      {:ok, tag}
    else
      Localize.AcceptLanguage.supported_match(tag, nil)
    end
  end

  defp supported_match(tag, _locale) do
    Localize.AcceptLanguage.supported_match(tag, nil)
  end

  defp validate_from(options, nil), do: Keyword.put(options, :from, @default_from)

  defp validate_from(options, from) when is_atom(from) do
    options
    |> Keyword.put(:from, [from])
    |> validate_from([from])
  end

  defp validate_from(options, from) when is_list(from) do
    Enum.each(from, fn f ->
      if invalid_from?(f) do
        raise ArgumentError,
              "Invalid :from option #{inspect(f)} detected. " <>
                "Valid :from options are #{inspect(@from_options)}"
      end
    end)

    options
  end

  defp invalid_from?(from) when from in @from_options, do: false

  defp invalid_from?({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: false

  defp invalid_from?({module, function})
       when is_atom(module) and is_atom(function),
       do: false

  defp invalid_from?(_other), do: true

  defp validate_param(options, nil), do: Keyword.put(options, :param, @default_param_name)
  defp validate_param(options, param) when is_binary(param), do: options

  defp validate_param(_options, param) do
    raise ArgumentError,
          "Invalid :param #{inspect(param)} detected. :param must be a string"
  end

  # When no :default is given, store a sentinel rather than calling
  # Localize.default_locale() eagerly. Plug.init/1 runs at compile time
  # inside Phoenix router pipelines; calling into Localize there forces
  # the CLDR data modules to load in the compiler VM, which can exhaust
  # memory on constrained builders. The sentinel is resolved to the real
  # default locale in default/2 at request time.
  defp validate_default(options, nil) do
    Keyword.put(options, :default, :__localize_default__)
  end

  defp validate_default(options, :none) do
    Keyword.put(options, :default, nil)
  end

  defp validate_default(options, {module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    Keyword.put(options, :default, {module, function, args})
  end

  defp validate_default(options, {module, function})
       when is_atom(module) and is_atom(function) do
    Keyword.put(options, :default, {module, function, []})
  end

  defp validate_default(options, default) do
    case Localize.validate_locale(default) do
      {:ok, locale} -> Keyword.put(options, :default, locale)
      {:error, %{__exception__: true} = exception} -> raise exception
    end
  end

  defp validate_gettext(options, nil), do: Keyword.put(options, :gettext, [])

  defp validate_gettext(options, backend) when is_atom(backend) do
    validate_gettext(options, [backend])
  end

  defp validate_gettext(options, backends) when is_list(backends) do
    Enum.each(backends, fn backend ->
      case Code.ensure_compiled(backend) do
        {:error, _} ->
          raise ArgumentError, "Gettext module #{inspect(backend)} is not known"

        {:module, _} ->
          :ok
      end
    end)

    Keyword.put(options, :gettext, backends)
  end

  defp validate_supported(options, supported) do
    Keyword.put(options, :supported, supported_option(supported))
  end

  @doc false
  # Validates a `:supported` option when a plug is initialised, which in a
  # Phoenix router is at compile time. Entries are checked for their type
  # only: validating them as locales would load CLDR data into the
  # compiler. `Localize.Plug.AcceptLanguage` validates its own option here.
  def supported_option(nil) do
    nil
  end

  def supported_option(supported) when is_list(supported) do
    Enum.each(supported, fn entry ->
      if not supported_entry?(entry) do
        raise ArgumentError,
              "Invalid :supported entry #{inspect(entry)} detected. Each entry must be " <>
                "a locale identifier string or atom, or a Localize.LanguageTag"
      end
    end)

    supported
  end

  def supported_option({module, function, args} = supported)
      when is_atom(module) and is_atom(function) and is_list(args) do
    supported
  end

  def supported_option({module, function}) when is_atom(module) and is_atom(function) do
    {module, function, []}
  end

  def supported_option(supported) do
    raise ArgumentError,
          "Invalid :supported #{inspect(supported)} detected. :supported must be a list " <>
            "of locales, or a {Module, function} or {Module, function, args} tuple"
  end

  defp supported_entry?(entry) when is_binary(entry) or is_atom(entry) do
    true
  end

  defp supported_entry?(%Localize.LanguageTag{}) do
    true
  end

  defp supported_entry?(_entry) do
    false
  end

  @doc false
  # The supported locales for a request: `nil` for the locales configured
  # for Localize, or a list. A function is called with the `conn` and the
  # plug's options. One that returns anything but a list is a defect in
  # the application, and no locale is then taken from the request, so that
  # a locale outside the application's own list is never chosen.
  def supported_locales(conn, options) do
    case options[:supported] do
      {module, function, args} -> call_supported(conn, options, module, function, args)
      supported -> supported
    end
  end

  defp call_supported(conn, options, module, function, args) do
    case apply(module, function, [conn, options | args]) do
      supported when is_list(supported) ->
        supported

      other ->
        Logger.warning(
          "#{inspect(module)}.#{function} returned #{inspect(other)} for the :supported " <>
            "option, where a list of locales is expected. No locale is taken from the request."
        )

        []
    end
  end

  defp validate_vary(options, nil) do
    Keyword.put(options, :vary, true)
  end

  defp validate_vary(options, vary) when is_boolean(vary) do
    options
  end

  defp validate_vary(_options, vary) do
    raise ArgumentError,
          "Invalid :vary #{inspect(vary)} detected. :vary must be true or false"
  end

  defp validate_content_language(options, nil) do
    Keyword.put(options, :content_language, false)
  end

  defp validate_content_language(options, content_language) when is_boolean(content_language) do
    options
  end

  defp validate_content_language(_options, content_language) do
    raise ArgumentError,
          "Invalid :content_language #{inspect(content_language)} detected. " <>
            ":content_language must be true or false"
  end

  defp validate_session_key(options, nil) do
    Keyword.put(options, :session_key, @session_key)
  end

  defp validate_session_key(options, session_key)
       when is_binary(session_key) and byte_size(session_key) > 0 do
    options
  end

  defp validate_session_key(_options, session_key) do
    raise ArgumentError,
          "Invalid :session_key #{inspect(session_key)} detected. :session_key must be a non-empty string"
  end
end
