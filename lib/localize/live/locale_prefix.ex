if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Localize.Live.LocalePrefix do
    @moduledoc """
    A LiveView `on_mount` hook that applies `Localize.Plug.LocalePrefix`'s URL mode on each live navigation.

    A `push_patch` or a `navigate` within one live session reaches `handle_params/3`, not the router's pipeline, so the plug does not see it. This hook attaches a `handle_params` hook that makes the same decision, with `Localize.Routes.Prefix.target/3`, for the URI of every navigation:

    * A prefixed address sets the locale it names, for Localize and Gettext.

    * Under `:prefix_others`, an address with no prefix sets the default locale, and the default locale's prefix is redirected to the address without it.

    * Under `:prefix_all`, an address with no prefix is redirected to the address in the current locale, or in the default locale when `:exists?` says the page does not exist in it.

    * A locale parameter that names no supported locale raises `Localize.Plug.LocalePrefix.NotFoundError`. On a connected LiveView that ends the process, the browser loads the address over HTTP, and the plug answers it with a `404`.

    A redirect is a `push_navigate`, and keeps the query string.

    ### Settings

    The hook uses the settings `Localize.Plug.LocalePrefix` resolved for the request that rendered the page: its URL mode, default locale, supported locales, locale parameter and `:exists?` test. `session/1`, given as the `:session` of the live session, signs them into the page with the locale `Localize.Plug.PutLocale` set, without writing the session cookie, so a site whose settings are functions of the request resolves them once and every navigation in the live session uses them. An `:exists?` function is called with a `t:Localize.Routes.Request.t/0` built from the navigation's URI, the session and the socket's assigns.

    The hook also puts the settings on the socket, where `Localize.Routes.Prefix.localized_path/3` reads them: `localized_path(@socket, ~p"/about")`.

    ### Options

    The hook is given as `Localize.Live.LocalePrefix` or as `{Localize.Live.LocalePrefix, options}`, where `options` is a keyword list:

    * `:gettext` is a Gettext backend, or a list of them, whose locale is set with Localize's. The default is none.

    * `:session_key` is the session key the locale is read from on mount, the `:session_key` given to `Localize.Plug.PutLocale`. The default is `Localize.Plug.PutLocale`'s.

    ### Re-rendering

    A LiveView re-renders what depends on assigns that changed, and changing the locale changes no assign. A navigation to the same page in another language should be a `navigate`, which mounts the LiveView again in the new locale, rather than a `push_patch`. `Localize.HTML.LanguageSwitcher.language_switcher/1` links with `navigate` when given `navigate`.

    ### Example

        pipeline :browser do
          plug :fetch_session
          plug Localize.Plug.PutLocale, from: [:path_prefix, :session, :accept_language]
          plug Localize.Plug.LocalePrefix, mode: :prefix_all
        end

        live_session :default,
          on_mount: [{Localize.Live.LocalePrefix, gettext: MyApp.Gettext}],
          session: {Localize.Live.LocalePrefix, :session, []} do
          locale_prefix do
            live "/about", AboutLive
          end
        end

    """

    import Phoenix.LiveView, only: [attach_hook: 4, push_navigate: 2, put_private: 3]
    require Logger

    alias Localize.Plug.LocalePrefix, as: PrefixPlug
    alias Localize.Routes.{Prefix, Request}

    @session_key "localize_locale_prefix"
    @private_key :localize_locale_prefix
    @modes [:prefix_others, :prefix_all]

    @doc """
    Returns the session a live session hands its LiveViews: the locale `Localize.Plug.PutLocale` set and the settings `Localize.Plug.LocalePrefix` resolved for the request.

    It is given as the `:session` of a live session, `session: {Localize.Live.LocalePrefix, :session, []}`, where LiveView calls it with the `conn` of the request that renders the page and signs the result into the page. It replaces `Localize.Plug.live_session_locale/1`, whose locale it includes.

    ### Arguments

    * `conn` is the `t:Plug.Conn.t/0` of the request, which `Localize.Plug.PutLocale` and `Localize.Plug.LocalePrefix` have been through.

    ### Returns

    * A map of session keys to values, which holds no settings when `Localize.Plug.LocalePrefix` has not run.

    ### Examples

        iex> Localize.Live.LocalePrefix.session(Plug.Test.conn(:get, "/"))
        %{}

    """
    @spec session(Plug.Conn.t()) :: map()
    def session(%Plug.Conn{} = conn) do
      locale_session = Localize.Plug.live_session_locale(conn)
      settings = PrefixPlug.get_settings(conn)

      if is_nil(settings) do
        locale_session
      else
        Map.put(locale_session, @session_key, compact(settings))
      end
    end

    @doc """
    Sets the locale from the session and attaches the `handle_params` hook.

    ### Arguments

    * `options` is `:default` or the keyword list of options described in the module documentation.

    * `params` is the LiveView's parameters.

    * `session` is the LiveView's session.

    * `socket` is the LiveView's socket.

    ### Returns

    * `{:cont, socket}`.

    """
    @spec on_mount(atom() | Keyword.t(), map() | atom(), map(), Phoenix.LiveView.Socket.t()) ::
            {:cont, Phoenix.LiveView.Socket.t()}
    def on_mount(:default, params, session, socket) do
      on_mount([], params, session, socket)
    end

    def on_mount(options, _params, session, socket) when is_list(options) do
      backends = gettext_backends(options)

      _locale =
        Localize.Plug.put_locale_from_session(
          session,
          Keyword.take(options, [:gettext, :session_key])
        )

      case expand(Map.get(session, @session_key)) do
        {:ok, settings} ->
          context = %{settings: settings, session: session, gettext: backends}

          socket =
            socket
            |> put_private(@private_key, Map.delete(settings, :exists?))
            |> attach_hook(@private_key, :handle_params, fn _params, uri, socket ->
              navigate(uri, socket, context)
            end)

          {:cont, socket}

        :error ->
          Logger.warning(
            "Localize.Live.LocalePrefix: the session holds no settings of Localize.Plug.LocalePrefix. " <>
              "Give {Localize.Live.LocalePrefix, :session, []} as the :session of the live session. " <>
              "Navigations are not checked."
          )

          {:cont, socket}
      end
    end

    def on_mount(options, params, session, socket) do
      Logger.warning(
        "Localize.Live.LocalePrefix: options must be :default or a keyword list, got: #{inspect(options)}"
      )

      on_mount([], params, session, socket)
    end

    defp navigate(uri, socket, context) do
      settings = context.settings
      %URI{host: host, path: uri_path, query: query} = URI.parse(uri)
      {script, path} = Prefix.__split_script__(uri_path || "/", socket)
      check_locale_param!(socket, host, path, settings)

      request = %Request{
        host: host,
        path: path,
        session: context.session,
        assigns: socket.assigns
      }

      target =
        Prefix.target(path, Localize.get_locale(),
          mode: settings.mode,
          default: settings.default,
          supported: settings.supported,
          exists?: PrefixPlug.exists_test(request, settings.exists?)
        )

      apply_target(target, socket, script, query, context)
    end

    defp apply_target({:serve, locale}, socket, _script, _query, context) do
      if not same_locale?(Localize.get_locale(), locale) do
        put_locale(locale, context.gettext)
      end

      {:cont, socket}
    end

    defp apply_target({:redirect, to, _status}, socket, script, query, _context) do
      {:halt, push_navigate(socket, to: script <> to <> query_string(query))}
    end

    defp apply_target({:error, exception}, socket, _script, _query, _context) do
      Logger.warning(
        "Localize.Live.LocalePrefix: #{Exception.message(exception)}. The navigation is not checked."
      )

      {:cont, socket}
    end

    # A locale parameter must name a supported locale exactly, as the plug
    # requires: `/blog/about` matched by `/:locale/about` is not a page. The
    # parameter is read from the route the path matches, since the params a
    # `handle_params` hook receives hold the query string's too, and
    # `?locale=blog` on a page with no locale in its route is still a page.
    defp check_locale_param!(socket, host, path, settings) do
      value = path_param(socket.router, host, path, settings.param)

      if is_binary(value) and not PrefixPlug.supported_prefix?(value, settings.supported) do
        raise PrefixPlug.NotFoundError, path: path, locale: value
      end
    end

    defp path_param(router, host, path, param) when is_atom(router) and not is_nil(router) do
      case Phoenix.Router.route_info(router, "GET", path, host || "") do
        %{path_params: path_params} -> Map.get(path_params, param)
        :error -> nil
      end
    end

    defp path_param(_router, _host, _path, _param) do
      nil
    end

    defp same_locale?(%Localize.LanguageTag{} = current, %Localize.LanguageTag{} = locale) do
      current.canonical_locale_id == locale.canonical_locale_id
    end

    defp same_locale?(_current, _locale) do
      false
    end

    defp put_locale(locale, backends) do
      Localize.put_locale(locale)
      Enum.each(backends, &put_gettext_locale(&1, locale))
    end

    defp put_gettext_locale(backend, locale) do
      case Localize.Locale.gettext_locale_id(locale, backend) do
        {:ok, gettext_locale} -> Gettext.put_locale(backend, gettext_locale)
        {:error, _reason} -> :ok
      end
    end

    defp query_string(nil) do
      ""
    end

    defp query_string("") do
      ""
    end

    defp query_string(query) do
      "?" <> query
    end

    defp gettext_backends(options) do
      case Keyword.get(options, :gettext, []) do
        backend when is_atom(backend) -> [backend]
        backends when is_list(backends) -> Enum.filter(backends, &is_atom/1)
        _other -> []
      end
    end

    # The settings in the session, as strings and atoms that sign compactly
    # into the page.
    defp compact(settings) do
      %{
        "mode" => settings.mode,
        "default" => locale_string(settings.default),
        "supported" => supported_strings(settings.supported),
        "param" => settings.param,
        "exists?" => Map.get(settings, :exists?)
      }
    end

    defp expand(%{"mode" => mode} = settings) when mode in @modes do
      {:ok,
       %{
         mode: mode,
         default: settings["default"],
         supported: settings["supported"],
         param: settings["param"] || "locale",
         exists?: settings["exists?"]
       }}
    end

    defp expand(_settings) do
      :error
    end

    defp supported_strings(nil) do
      nil
    end

    defp supported_strings(supported) do
      Enum.map(supported, &locale_string/1)
    end

    defp locale_string(%Localize.LanguageTag{} = locale) do
      Localize.LanguageTag.to_string(locale)
    end

    defp locale_string(locale) when is_atom(locale) and not is_nil(locale) do
      Atom.to_string(locale)
    end

    defp locale_string(locale) do
      locale
    end
  end
end
