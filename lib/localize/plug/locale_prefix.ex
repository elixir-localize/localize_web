defmodule Localize.Plug.LocalePrefix do
  @moduledoc """
  Plug that applies a URL mode to the locale prefix of a request: it redirects an address that is not the page's address in its language, and answers a prefix naming no supported locale with a `404`.

  It runs after `Localize.Plug.PutLocale`, whose settings it shares: the supported locales, the default locale and the name of the locale parameter are `PutLocale`'s unless given here. The decision is `Localize.Routes.Prefix.target/3`'s:

  * Under `:prefix_others`, the default, the default locale has no prefix. `/en/about`, where English is the default, is redirected with a `301` to `/about`, and `/about` is served in the default locale, whatever locale `PutLocale` found in the session or `accept-language`.

  * Under `:prefix_all`, every locale has a prefix. `/about` is redirected with a `302` to the address in the locale `PutLocale` found, `/fr/about`, or in the default locale when `:exists?` says the page does not exist in it.

  * A prefixed address is served in the locale its prefix names.

  A redirect keeps the query string, and is made only for a `GET` or `HEAD` request, since a browser follows a redirect of any other method with a `GET`; other requests are served in the locale `PutLocale` set. A `302` depends on the visitor, and carries the `vary` header `PutLocale` added for the sources it read. Under `:prefix_others` the address alone decides, so `PutLocale`'s `:from` needs only `:path_prefix` or `:path`: a source after it adds a `vary` the response does not need.

  When the plug serves a locale other than the one `PutLocale` set, it sets that locale as `PutLocale` would, for Localize, Gettext and the `content-language` header.

  ### Unsupported locale parameters

  A route declared with `Localize.Routes.locale_prefix/2` captures any first segment in its locale parameter, so `/blog/about` matches `/:locale/about` with `"blog"`. When the parameter names no supported locale, the plug raises `Localize.Plug.LocalePrefix.NotFoundError`, whose `plug_status` is `404`, so Phoenix renders the application's own not-found page, as it does for an address no route matches. The parameter is read from `conn.path_params`, which is set once the router has matched, so the test applies when the plug is in a router pipeline.

  ### Example

      pipeline :browser do
        plug :fetch_session
        plug Localize.Plug.PutLocale, from: [:path_prefix, :session, :accept_language]
        plug Localize.Plug.LocalePrefix, mode: :prefix_all
      end

  A site among many takes its settings from the request:

      plug Localize.Plug.PutLocale,
        from: [:path_prefix, :session, :accept_language],
        supported: {MyApp.Sites, :locales}

      plug Localize.Plug.LocalePrefix,
        mode: {MyApp.Sites, :url_mode},
        default: {MyApp.Sites, :default_locale},
        exists?: {MyApp.Pages, :published?}

  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  alias Localize.Plug.PutLocale
  alias Localize.Routes.{Prefix, Request}

  @private_key :localize_locale_prefix
  @modes [:prefix_others, :prefix_all]
  @options [:mode, :default, :supported, :exists?, :param]
  @redirect_methods ["GET", "HEAD"]

  defmodule NotFoundError do
    @moduledoc """
    Raised by `Localize.Plug.LocalePrefix` when a request's locale parameter names no supported locale, such as `"blog"` in `/blog/about` matched by `/:locale/about`. Its `plug_status` is `404`, so Phoenix answers with the application's not-found page.

    """

    defexception [:path, :locale, plug_status: 404]

    @typedoc "The requested path and the parameter's value."
    @type t :: %__MODULE__{path: String.t(), locale: String.t(), plug_status: 404}

    @impl true
    def message(%__MODULE__{path: path, locale: locale}) do
      "no page at #{path}: #{inspect(locale)} is not a supported locale"
    end
  end

  @doc """
  Validates the plug's options.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * `:mode` is the URL mode, `:prefix_others` or `:prefix_all`, or a `{Module, function}` or `{Module, function, args}` tuple whose function is called with the request as a `t:Localize.Routes.Request.t/0`, followed by `args`, and returns it. The default is `:prefix_others`.

  * `:default` is the default locale, which has no prefix under `:prefix_others`, or a function that returns it, called as for `:mode`. The default is `Localize.Plug.PutLocale`'s default locale, and else `Localize.default_locale/0`.

  * `:supported` is the list of supported locales, or a function that returns it, called as for `:mode`. The default is the list `Localize.Plug.PutLocale` matched the request against.

  * `:exists?` is a `{Module, function}` or `{Module, function, args}` tuple whose function is called with the request as a `t:Localize.Routes.Request.t/0`, the path without its prefix and the locale as a `t:Localize.LanguageTag.t/0`, followed by `args`, and returns whether the page exists in that locale. It is consulted only for a `302` under `:prefix_all`. The default is none: every page exists in every locale.

  * `:param` is the name of the path parameter holding the locale. The default is `Localize.Plug.PutLocale`'s `:param`, `"locale"`.

  ### Returns

  * The validated options.

  An option that is not valid raises an `ArgumentError`, when the router or endpoint that declares the plug is compiled.

  ### Examples

      iex> Localize.Plug.LocalePrefix.init(mode: :prefix_all)
      [mode: :prefix_all]

  """
  @impl Plug
  def init(options) do
    if not Keyword.keyword?(options) do
      raise ArgumentError,
            "Localize.Plug.LocalePrefix expects a keyword list of options, got: " <>
              inspect(options)
    end

    case Keyword.keys(options) -- @options do
      [] ->
        Enum.each(options, &validate_option!/1)
        options

      unknown ->
        raise ArgumentError,
              "Localize.Plug.LocalePrefix takes the options #{inspect(@options)}, got: " <>
                inspect(unknown)
    end
  end

  @doc """
  Applies the URL mode to a request.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0` that `Localize.Plug.PutLocale` has run on.

  * `options` is the keyword list `init/1` returned.

  ### Returns

  * The `conn`, redirected and halted, with its locale replaced, or as it was. With no `Localize.Plug.PutLocale` before it, or when an option resolves to a value that is not valid, the plug logs a warning and returns the `conn` as it was.

  ### Examples

  The plug is called from a router pipeline, after `Localize.Plug.PutLocale`:

      pipeline :browser do
        plug :fetch_session
        plug Localize.Plug.PutLocale, from: [:path_prefix, :session, :accept_language]
        plug Localize.Plug.LocalePrefix, mode: :prefix_all
      end

  """
  @impl Plug
  def call(conn, options) do
    settings = PutLocale.__settings__(conn)

    if is_nil(settings) do
      Logger.warning(
        "Localize.Plug.LocalePrefix runs after Localize.Plug.PutLocale, which has not run " <>
          "for #{conn.request_path}. The request is passed on unchanged."
      )

      conn
    else
      resolve_and_route(conn, options, settings)
    end
  end

  @doc """
  Returns the settings `Localize.Plug.LocalePrefix` resolved for a request.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * A map with `:mode`, `:default`, `:supported`, `:param` and `:exists?`, as the plug resolved them for the request, or

  * `nil` when the plug has not run on `conn`.

  ### Examples

      iex> Localize.Plug.LocalePrefix.get_settings(%Plug.Conn{})
      nil

  """
  @spec get_settings(term()) :: map() | nil
  def get_settings(%Plug.Conn{private: private}) do
    private[@private_key]
  end

  def get_settings(_conn) do
    nil
  end

  defp resolve_and_route(conn, options, settings) do
    case resolve(conn, options, settings) do
      {:ok, resolved} ->
        conn
        |> put_private(@private_key, Map.delete(resolved, :exists_test))
        |> route(resolved)

      {:error, exception} ->
        warn(conn, exception)
    end
  end

  defp resolve(conn, options, settings) do
    request = Request.from_conn(conn)

    with {:ok, mode} <- mode(resolve_option(request, Keyword.get(options, :mode, :prefix_others))),
         {:ok, supported} <- supported(request, options, settings) do
      exists = Keyword.get(options, :exists?)

      {:ok,
       %{
         mode: mode,
         default: default(conn, request, options, settings),
         supported: supported,
         param: Keyword.get(options, :param) || Keyword.get(settings, :param, "locale"),
         exists?: exists,
         exists_test: exists_test(request, exists)
       }}
    end
  end

  defp route(conn, resolved) do
    check_locale_param!(conn, resolved)
    path = "/" <> Enum.join(conn.path_info, "/")

    target =
      Prefix.target(path, PutLocale.get_locale(conn),
        mode: resolved.mode,
        default: resolved.default,
        supported: resolved.supported,
        exists?: resolved.exists_test
      )

    apply_target(conn, target, path, resolved)
  end

  defp apply_target(conn, {:serve, locale}, path, resolved) do
    if same_locale?(PutLocale.get_locale(conn), locale) do
      conn
    else
      PutLocale.__put_locale__(conn, locale, served_source(path, resolved))
    end
  end

  defp apply_target(%Plug.Conn{method: method} = conn, {:redirect, to, status}, _path, _resolved)
       when method in @redirect_methods do
    conn
    |> put_resp_header("location", location(conn, to))
    |> send_resp(status, "")
    |> halt()
  end

  defp apply_target(conn, {:redirect, _to, _status}, _path, _resolved) do
    conn
  end

  defp apply_target(conn, {:error, exception}, _path, _resolved) do
    warn(conn, exception)
  end

  # A locale parameter must name a supported locale exactly, as a path
  # prefix must: `/blog/about` matched by `/:locale/about` is not a page.
  defp check_locale_param!(conn, resolved) do
    value = path_param(conn, resolved.param)

    if is_binary(value) and not supported_prefix?(value, resolved.supported) do
      raise NotFoundError, path: conn.request_path, locale: value
    end
  end

  defp path_param(%Plug.Conn{path_params: params}, param) do
    Map.get(params, param)
  end

  @doc false
  # Whether a locale parameter names a supported locale exactly.
  # `Localize.Live.LocalePrefix` applies the same test on a navigation.
  def supported_prefix?(value, supported) do
    case Prefix.split("/" <> value, supported) do
      {:ok, {%Localize.LanguageTag{}, "/"}} -> true
      _other -> false
    end
  end

  # A locale served for a prefixed address was chosen in the URL; one
  # served for an address without a prefix is the default.
  defp served_source(path, resolved) do
    case Prefix.split(path, resolved.supported) do
      {:ok, {nil, _path}} -> :default
      _prefixed -> :path_prefix
    end
  end

  defp same_locale?(%Localize.LanguageTag{} = current, %Localize.LanguageTag{} = locale) do
    current.canonical_locale_id == locale.canonical_locale_id
  end

  defp same_locale?(_current, _locale) do
    false
  end

  defp location(conn, to) do
    script = Enum.map_join(conn.script_name, &("/" <> &1))

    if conn.query_string == "" do
      script <> to
    else
      script <> to <> "?" <> conn.query_string
    end
  end

  @doc false
  # An option's value, calling it with the request when it is a function.
  # `Localize.Live.LocalePrefix` resolves options the same way.
  def resolve_option(%Request{} = request, {module, function}) do
    apply(module, function, [request])
  end

  def resolve_option(%Request{} = request, {module, function, args}) do
    apply(module, function, [request | args])
  end

  def resolve_option(_request, value) do
    value
  end

  defp mode(mode) when mode in @modes do
    {:ok, mode}
  end

  defp mode(mode) do
    {:error,
     Localize.InvalidValueError.exception(
       value: mode,
       expected: "one of #{inspect(@modes)} for the :mode option"
     )}
  end

  defp supported(request, options, settings) do
    supported =
      if Keyword.has_key?(options, :supported) do
        resolve_option(request, options[:supported])
      else
        Keyword.get(settings, :supported)
      end

    if is_list(supported) or is_nil(supported) do
      {:ok, supported}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: supported,
         expected: "a list of locales for the :supported option"
       )}
    end
  end

  defp default(conn, request, options, settings) do
    if Keyword.has_key?(options, :default) do
      resolve_option(request, options[:default])
    else
      PutLocale.__default_locale__(conn, settings) || Localize.default_locale()
    end
  end

  @doc false
  # The `:exists?` option as the two-argument test `Localize.Routes.Prefix`
  # takes, calling the application's function with the request.
  def exists_test(_request, nil) do
    nil
  end

  def exists_test(%Request{} = request, {module, function}) do
    fn rest, locale -> apply(module, function, [request, rest, locale]) end
  end

  def exists_test(%Request{} = request, {module, function, args}) do
    fn rest, locale -> apply(module, function, [request, rest, locale | args]) end
  end

  defp warn(conn, exception) do
    Logger.warning(
      "Localize.Plug.LocalePrefix: #{Exception.message(exception)}. " <>
        "The request for #{conn.request_path} is passed on unchanged."
    )

    conn
  end

  defp validate_option!({:mode, mode}) when mode in @modes do
    :ok
  end

  defp validate_option!({:default, %Localize.LanguageTag{}}) do
    :ok
  end

  defp validate_option!({:default, default}) when is_binary(default) or is_atom(default) do
    :ok
  end

  defp validate_option!({:supported, supported}) when is_list(supported) or is_nil(supported) do
    :ok
  end

  defp validate_option!({:exists?, nil}) do
    :ok
  end

  defp validate_option!({:param, param}) when is_binary(param) and byte_size(param) > 0 do
    :ok
  end

  defp validate_option!({option, {module, function}})
       when option in [:mode, :default, :supported, :exists?] and is_atom(module) and
              is_atom(function) do
    :ok
  end

  defp validate_option!({option, {module, function, args}})
       when option in [:mode, :default, :supported, :exists?] and is_atom(module) and
              is_atom(function) and is_list(args) do
    :ok
  end

  defp validate_option!({option, value}) do
    raise ArgumentError,
          "Localize.Plug.LocalePrefix: invalid #{inspect(option)} option #{inspect(value)}"
  end
end
