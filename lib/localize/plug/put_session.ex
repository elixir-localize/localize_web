defmodule Localize.Plug.PutSession do
  @moduledoc """
  Plug that persists the locale discovered by `Localize.Plug.PutLocale` into the session.

  The session key is fixed to `"#{Localize.Plug.PutLocale.session_key()}"` so that downstream functions like LiveView `on_mount` callbacks can retrieve the locale without needing additional configuration.

  By default every locale is stored, whatever source it came from. That includes a locale that was only inferred from the `accept-language` header, so a first visit writes the session and its response sets a cookie. The `:from` option stores a locale only when the visitor chose it.

  ### Options

  * `:as` determines the format in which the locale is saved in the session. The valid settings are:

    * `:string` in which the current locale is converted to a string before storing in the session. It will then be parsed back into a `%Localize.LanguageTag{}` upon reading it from the session. This option minimises space used in the session at the expense of CPU time to serialize and parse.

    * `:language_tag` in which the current locale is stored in the session in its native `%Localize.LanguageTag{}` format. This minimizes CPU time at the expense of larger session storage.

    The default is `as: :string`.

  * `:from` is a list of the sources whose locale is stored: any of the names the `:from` option of `Localize.Plug.PutLocale` accepts, the `{Module, function}` and `{Module, function, args}` sources given to it, and `:default` for the locale its `:default` option supplies. A locale that `Localize.Plug.PutLocale` found in a source that is not listed is not stored, and a locale already in the session is left as it is. The default is `:all`, which stores a locale from any source.

  The plug writes the session only when the locale it stores differs from the one already there. `stored?/1` says whether it did for a request, which an application that sends `cache-control: public` needs in order to send `private` on a response that sets the session cookie.

  > #### LiveView and a locale that is not stored {: .warning}
  >
  > A connected LiveView cannot read the `accept-language` header, so it takes the locale from the session. With a `:from` that leaves `:accept_language` out, a visitor who has not chosen a locale has none in the session cookie, and the LiveView mounts in the default locale. Pass `Localize.Plug.live_session_locale/1` as the `:session` of the live session, which hands the LiveView the locale the plug resolved without writing the cookie. `Localize.Routes.localize_live_session/3` does this already for localized routes.

  ### Examples

      plug Localize.Plug.PutLocale,
        from: [:path, :query],
        gettext: MyApp.Gettext
      plug Localize.Plug.PutSession, as: :string

      # Store a locale the visitor chose, in the URL or a form, and not one
      # inferred from the accept-language header or the default.
      plug Localize.Plug.PutLocale
      plug Localize.Plug.PutSession, from: [:route, :path, :query, :body]

  """

  alias Localize.Plug.PutLocale
  import Plug.Conn

  @formats [:string, :language_tag]

  # Set in `conn.private` when the plug writes the locale to the session.
  @stored_key :localize_locale_stored

  @doc false
  def init(options \\ []) when is_list(options) do
    {as, options} = Keyword.pop(options, :as, :string)
    {from, options} = Keyword.pop(options, :from, :all)

    validate_as(as)
    validate_from(from)
    validate_no_others(options)

    %{as: as, from: from}
  end

  @doc false
  def call(conn, %{as: as, from: from}) do
    locale = PutLocale.get_locale(conn)
    source = PutLocale.get_locale_source(conn)

    if store?(locale, source, from) do
      put_locale(conn, format(locale, as))
    else
      conn
    end
  end

  @doc """
  Returns whether `Localize.Plug.PutSession` wrote the locale to the session for this request.

  The plug writes the session only when the locale it stores differs from the one already there, and a response that writes the session sets the session cookie. Such a response is made for one visitor and should not be stored by a shared cache. An application that sends `cache-control: public` on its pages can use this function to send `private` on those responses instead.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * `true` when the plug wrote the locale to the session for this request, or

  * `false` when it did not, when the plug has not run, or when `conn` is not a `t:Plug.Conn.t/0`.

  ### Examples

      iex> Localize.Plug.PutSession.stored?(%Plug.Conn{})
      false

      # In a plug that runs after `Localize.Plug.PutSession`.
      def put_cache_control(conn, _options) do
        if Localize.Plug.PutSession.stored?(conn) do
          Plug.Conn.put_resp_header(conn, "cache-control", "private")
        else
          Plug.Conn.put_resp_header(conn, "cache-control", "public, max-age=60")
        end
      end

  """
  @spec stored?(term()) :: boolean()
  def stored?(%Plug.Conn{private: private}) do
    Map.get(private, @stored_key, false)
  end

  def stored?(_conn) do
    false
  end

  defp store?(%Localize.LanguageTag{}, _source, :all) do
    true
  end

  defp store?(%Localize.LanguageTag{}, source, from) when is_list(from) do
    source in from
  end

  defp store?(_locale, _source, _from) do
    false
  end

  defp format(locale, :string) do
    Localize.LanguageTag.to_string(locale)
  end

  defp format(locale, :language_tag) do
    locale
  end

  # The session is written only when the locale it holds would change, so
  # that a response sets the session cookie no more often than it must.
  defp put_locale(conn, locale) do
    conn = fetch_session(conn)

    if get_session(conn, PutLocale.session_key()) == locale do
      conn
    else
      conn
      |> put_session(PutLocale.session_key(), locale)
      |> put_private(@stored_key, true)
    end
  end

  defp validate_as(as) when as in @formats do
    :ok
  end

  defp validate_as(as) do
    raise ArgumentError,
          "Invalid option for `:as`. Valid settings are :string or :language_tag. Found #{inspect(as)}"
  end

  defp validate_from(:all) do
    :ok
  end

  defp validate_from([_ | _] = from) do
    invalid = Enum.reject(from, &source?/1)

    if match?([_ | _], invalid) do
      raise ArgumentError,
            "Invalid option for `:from`. Valid entries are #{inspect(sources())}, " <>
              "{Module, function} and {Module, function, args}. Found #{inspect(invalid)}"
    else
      :ok
    end
  end

  defp validate_from(from) do
    raise ArgumentError,
          "Invalid option for `:from`. It must be :all or a list of sources. Found #{inspect(from)}"
  end

  defp source?({module, function}) when is_atom(module) and is_atom(function) do
    true
  end

  defp source?({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    true
  end

  defp source?(source) do
    source in sources()
  end

  # The sources `Localize.Plug.PutLocale` can find a locale in, and the
  # `:default` it records when none of them has one.
  defp sources do
    PutLocale.sources() ++ [:default]
  end

  defp validate_no_others([]) do
    :ok
  end

  defp validate_no_others(options) do
    raise ArgumentError,
          "Invalid options. Valid options are `:as` and `:from`. Found #{inspect(options)}"
  end
end
