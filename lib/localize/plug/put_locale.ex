defmodule Localize.Plug.PutLocale do
  @private_key :localize_locale
  @session_key "localize_locale"

  @default_from [:session, :accept_language, :query, :path, :route]
  @default_param_name "locale"

  @moduledoc """
  Plug that discovers and sets the locale for the current process.

  The locale can be derived from the accept-language header, a query parameter, a URL parameter, a body parameter, a cookie, the route, the session, or the hostname TLD. Sources are checked in the order specified by the `:from` option, and the first successful match wins.

  When a locale is found, `Localize.put_locale/1` is always called to set the process locale. If Gettext backends are configured, the locale is also set on each backend.

  If a locale is found then `conn.private[:localize_locale]` is also set. It can be retrieved with `Localize.Plug.PutLocale.get_locale/1`.

  ### Options

  * `:from` is a list specifying where in the request to look for the locale. The default is `#{inspect(@default_from)}`. The valid options are:

    * `:accept_language` will parse the `accept-language` header and find the best matched configured locale.

    * `:path` will look for a locale by examining `conn.path_params`.

    * `:query` will look for a locale by examining `conn.query_params`.

    * `:body` will look for a locale by examining `conn.body_params`.

    * `:cookie` will look for a locale in the request cookie(s).

    * `:session` will look for a locale in the session.

    * `:route` will look for a locale in the route that was matched under the key `private.#{inspect(@private_key)}`.

    * `:host` will attempt to resolve a locale from the hostname top-level domain.

    * `{Module, function, args}` in which case the indicated function will be called. If it returns `{:ok, locale}` then the locale is set. `locale` must be a `t:Localize.LanguageTag.t/0`.

    * `{Module, function}` in which case the function is called with `conn` and `options` as its two arguments.

  * `:default` is the default locale to set if no locale is found by other configured methods. It can be a string like `"en"` or a `Localize.LanguageTag` struct. It may also be `:none` to indicate that no locale is to be set by default. Lastly, it may also be a `{Module, function, args}` or `{Module, function}` tuple. The default is `Localize.default_locale/0` (resolved at runtime, not compile time).

  * `:gettext` is a Gettext backend module or a list of Gettext backend modules on which the locale will be set. The default is `[]` (no Gettext backends).

  * `:param` is the name of the parameter to look for in the query, path, body, or cookie. The default is `"locale"`.

  ### Examples

      plug Localize.Plug.PutLocale,
        from: [:query, :path, :body, :cookie, :accept_language],
        param: "locale",
        gettext: MyApp.Gettext

      plug Localize.Plug.PutLocale,
        from: [:route, :session, :accept_language],
        gettext: [MyApp.Gettext, MyOtherApp.Gettext]

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

  @generic_tlds ~w(com org net edu gov mil int)

  @doc false
  def init(options) do
    options
    |> validate_from(options[:from])
    |> validate_param(options[:param])
    |> validate_gettext(options[:gettext])
    |> validate_default(options[:default])
  end

  @doc false
  def call(conn, options) do
    if locale = locale_from_params(conn, options[:from], options) || default(conn, options) do
      Localize.put_locale(locale)

      Enum.each(options[:gettext], fn gettext_backend ->
        put_gettext_locale(gettext_backend, locale)
      end)

      put_private(conn, @private_key, locale)
    else
      conn
    end
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

  @doc """
  Returns the locale set by `Localize.Plug.PutLocale`.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * A `t:Localize.LanguageTag.t/0` or `nil`.

  """
  def get_locale(conn) do
    conn.private[@private_key]
  end

  @doc """
  Attempts to resolve a locale from a hostname's top-level domain.

  Extracts the TLD, validates it as a territory code, and returns
  the best matching locale for that territory.

  ### Arguments

  * `host` is a hostname string (e.g., "example.co.uk").

  ### Returns

  * `{:ok, Localize.LanguageTag.t()}` or

  * `{:error, reason}`

  """
  def locale_from_host(nil), do: nil

  def locale_from_host(host) when is_binary(host) do
    tld =
      host
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    if tld in @generic_tlds do
      nil
    else
      territory = String.upcase(tld)

      case Localize.validate_territory(territory) do
        {:ok, territory_code} ->
          Localize.validate_locale("und-#{territory_code}")

        _error ->
          nil
      end
    end
  end

  defp locale_from_params(conn, from, options) do
    Enum.reduce_while(from, nil, fn param, _acc ->
      conn
      |> fetch_param(param, options[:param], options)
      |> return_if_valid_locale()
    end)
  end

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

  defp fetch_param(conn, :host, _param, _options) do
    conn
    |> Map.get(:host)
    |> locale_from_host()
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

  defp validate_locale_param(%Localize.LanguageTag{} = locale) do
    Localize.validate_locale(locale)
  end

  defp validate_locale_param(locale) do
    Localize.validate_locale(locale)
  end

  defp return_if_valid_locale({:ok, locale}) do
    {:halt, locale}
  end

  defp return_if_valid_locale(_) do
    {:cont, nil}
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
end
