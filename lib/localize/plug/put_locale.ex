defmodule Localize.Plug.PutLocale do
  @private_key :localize_locale
  @source_key :localize_locale_source
  @session_key "localize_locale"

  @default_from [:route, :path, :query, :session, :accept_language]
  @default_param_name "locale"

  @moduledoc """
  Plug that discovers and sets the locale for the current process.

  The locale can be derived from the accept-language header, a query parameter, a URL parameter, a body parameter, a cookie, the route, the session, or the hostname TLD. Sources are checked in the order specified by the `:from` option, and the first successful match wins.

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

  """

  import Plug.Conn
  require Logger

  @from_options [
    :accept_language,
    :path,
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
  end

  @doc false
  def call(conn, options) do
    {found, consulted} = locale_from_params(conn, options[:from], options)
    source = source(found, consulted)
    locale = found || default(conn, options)
    conn = put_vary(conn, consulted, options[:vary])

    if locale do
      Localize.put_locale(locale)

      Enum.each(options[:gettext], fn gettext_backend ->
        put_gettext_locale(gettext_backend, locale)
      end)

      conn
      |> put_private(@private_key, locale)
      |> put_private(@source_key, source)
    else
      conn
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

  ### Examples

      iex> Localize.Plug.PutLocale.session_key()
      "localize_locale"

  """
  def session_key do
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

  """
  def get_locale(%Plug.Conn{private: private}), do: private[@private_key]
  def get_locale(_conn), do: nil

  @doc """
  Returns the source that decided the locale set by `Localize.Plug.PutLocale`.

  This tells a locale the visitor chose, in the URL or a form, from one that was only inferred, from the `accept-language` header or the default. `Localize.Plug.PutSession` reads it to store the first kind and not the second.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * The entry of the `:from` option the locale was found in, such as `:query`, `:session` or `:accept_language`, or

  * `:default` when no source had a locale and the `:default` option supplied it, or

  * `nil` when no locale was set or `conn` is not a `t:Plug.Conn.t/0`.

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

  defp fetch_param(conn, :accept_language, _param, _options) do
    case get_req_header(conn, @language_header) do
      [accept_language | _] -> Localize.AcceptLanguage.best_match(accept_language)
      [] -> nil
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

  defp fetch_param(conn, :query, param, _options) do
    conn
    |> Map.get(:query_params)
    |> Map.get(param)
    |> validate_locale_param()
  end

  defp fetch_param(conn, :path, param, _options) do
    conn
    |> Map.get(:path_params)
    |> Map.get(param)
    |> validate_locale_param()
  end

  defp fetch_param(conn, :body, param, _options) do
    conn
    |> Map.get(:body_params)
    |> Map.get(param)
    |> validate_locale_param()
  end

  defp fetch_param(conn, :session, _param, _options) do
    conn
    |> get_session(@session_key)
    |> validate_locale_param()
  end

  defp fetch_param(conn, :cookie, param, _options) do
    conn
    |> Map.get(:cookies)
    |> Map.get(param)
    |> validate_locale_param()
  end

  defp fetch_param(conn, :host, _param, options) do
    conn
    |> Map.get(:host)
    |> locale_from_host(Keyword.take(options, [:generic_tlds]))
  end

  defp fetch_param(conn, :route, _param, _options) do
    conn
    |> Map.fetch!(:private)
    |> Map.get(@private_key)
    |> validate_locale_param()
  end

  defp fetch_param(conn, {module, function, args}, _param, options) do
    apply(module, function, [conn, options | args])
  end

  defp fetch_param(conn, {module, function}, _param, options) do
    apply(module, function, [conn, options])
  end

  defp validate_locale_param(nil), do: nil

  # The router, `Localize.Plug.AcceptLanguage` and this plug each store a tag
  # they validated, so a tag found here is trusted as it stands.
  defp validate_locale_param(%Localize.LanguageTag{cldr_locale_id: id} = locale)
       when not is_nil(id),
       do: {:ok, locale}

  defp validate_locale_param(locale) do
    Localize.validate_locale(locale)
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
end
