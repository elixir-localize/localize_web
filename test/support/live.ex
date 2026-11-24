defmodule MyAppWeb.LocaleHook do
  @moduledoc false

  def on_mount(:default, _params, session, socket) do
    _ = Localize.Plug.put_locale_from_session(session, gettext: MyApp.Gettext)
    {:cont, socket}
  end

  # A pipeline that keeps its locale under a session key of its own.
  def on_mount(:admin, _params, session, socket) do
    _ =
      Localize.Plug.put_locale_from_session(session,
        gettext: MyApp.Gettext,
        session_key: "admin_locale"
      )

    {:cont, socket}
  end

  def session(_conn, value), do: %{"extra" => value}
end

defmodule MyAppWeb.LocaleLive do
  @moduledoc false

  use Phoenix.LiveView

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       locale: Localize.LanguageTag.to_string(Localize.get_locale()),
       gettext: Gettext.get_locale(MyApp.Gettext),
       title: Gettext.dgettext(MyApp.Gettext, "routes", "video"),
       extra: session["extra"]
     )}
  end

  def render(assigns) do
    ~H"""
    <p id="locale">{@locale}</p>
    <p id="gettext">{@gettext}</p>
    <p id="title">{@title}</p>
    <p id="extra">{@extra}</p>
    """
  end
end

defmodule MyApp.LiveRouter do
  @moduledoc false

  use Phoenix.Router
  use Localize.Routes, gettext: MyApp.Gettext, helpers: false
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(Localize.Plug.PutLocale, gettext: MyApp.Gettext)
    plug(Localize.Plug.PutSession)
  end

  scope "/", MyAppWeb do
    pipe_through(:browser)

    localize_live_session :localized,
      on_mount: MyAppWeb.LocaleHook,
      session: {MyAppWeb.LocaleHook, :session, ["mfa"]} do
      localize do
        live("/#{locale}/video", LocaleLive)
        live("/#{locale}/audio", LocaleLive)
      end

      localize [:en, :fr] do
        live("/#{locale}/pair", LocaleLive)
      end
    end

    localize_live_session :mapped, on_mount: MyAppWeb.LocaleHook, session: %{"extra" => "map"} do
      localize "fr" do
        live("/#{locale}/mapped", LocaleLive)
      end
    end

    live_session :plain, on_mount: MyAppWeb.LocaleHook do
      live("/live", LocaleLive)
    end

    localize_live_session :keyed,
      on_mount: {MyAppWeb.LocaleHook, :admin},
      session_key: "admin_locale" do
      localize "de" do
        live("/#{locale}/keyed", LocaleLive)
      end
    end
  end

  # An admin that keeps its own locale, under a session key of its own, beside
  # the locale of the pages.
  pipeline :admin do
    plug(:fetch_session)

    plug(Localize.Plug.PutLocale,
      from: [:query, :session],
      gettext: MyApp.Gettext,
      session_key: "admin_locale"
    )

    plug(Localize.Plug.PutSession)
  end

  scope "/admin", MyAppWeb do
    pipe_through(:admin)

    live_session :admin,
      on_mount: {MyAppWeb.LocaleHook, :admin},
      session: {Localize.Plug, :live_session_locale, []} do
      live("/dashboard", LocaleLive)
    end
  end

  # The session stores only a locale the visitor chose, so a locale taken
  # from `accept-language` is not in the cookie when a LiveView connects.
  pipeline :chosen do
    plug(:fetch_session)
    plug(Localize.Plug.PutLocale, gettext: MyApp.Gettext)
    plug(Localize.Plug.PutSession, from: [:route, :path, :query, :body])
  end

  scope "/chosen", MyAppWeb do
    pipe_through(:chosen)

    live_session :cookie_only, on_mount: MyAppWeb.LocaleHook do
      live("/cookie-only", LocaleLive)
    end

    live_session :handed,
      on_mount: MyAppWeb.LocaleHook,
      session: {Localize.Plug, :live_session_locale, []} do
      live("/handed", LocaleLive)
    end
  end
end

defmodule MyApp.LiveEndpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :localize_web

  @session_options [store: :cookie, key: "_live", signing_salt: "localize_live"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(MyApp.LiveRouter)
end
