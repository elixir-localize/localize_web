defmodule Localize.Plug.PutSession do
  @moduledoc """
  Puts the locale in the session.

  The session key is fixed to be `#{Localize.Plug.PutLocale.session_key()}`
  in order that downstream functions like those in LiveView don't
  have to be passed options.

  ## Options

  * `:as` determines the format in which the locale is saved in
    the session. The valid settings are:

    * `:string` in which the current locale is converted to a
      string before storing in the session. It will then be parsed
      back into a `%Localize.LanguageTag{}` upon reading it from
      the session. This option minimises space used in the session
      at the expense of CPU time to serialize and parse.

    * `:language_tag` in which the current locale is stored in
      the session in its native `%Localize.LanguageTag{}` format.
      This minimizes CPU time at the expense of larger session
      storage.

  The default is `as: :string`.

  ## Examples

      plug Localize.Plug.PutLocale,
        apps: [:localize, :gettext],
        from: [:path, :query],
        gettext: MyApp.Gettext
      plug Localize.Plug.PutSession, as: :string

  """

  alias Localize.Plug.PutLocale
  import Plug.Conn

  @doc false
  def init(options \\ []) when is_list(options) do
    {as, options} = Keyword.pop(options, :as, :string)

    options_map =
      case as do
        :string ->
          %{as: :string}

        :language_tag ->
          %{as: :language_tag}

        other ->
          raise ArgumentError,
                "Invalid option for `:as`. Valid settings are :string or :language_tag. Found #{inspect(other)}"
      end

    if length(options) > 0,
      do:
        raise(ArgumentError, "Invalid options. Valid option is `:as`. Found #{inspect(options)}")

    options_map
  end

  @doc false
  def call(conn, %{as: as}) do
    case PutLocale.get_locale(conn) do
      %Localize.LanguageTag{} = locale ->
        conn = fetch_session(conn)

        stored_locale =
          if as == :string do
            Localize.LanguageTag.to_string(locale)
          else
            locale
          end

        put_session(conn, PutLocale.session_key(), stored_locale)

      _other ->
        conn
    end
  end
end
