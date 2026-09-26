defmodule Localize.VerifiedRoutes do
  @moduledoc """
  Localized verified routes using the `~q` sigil.

  This module provides compile-time verified localized routes. Instead of configuring with `use Phoenix.VerifiedRoutes`, configure instead:

      use Localize.VerifiedRoutes,
        router: MyApp.Router,
        endpoint: MyApp.Endpoint,
        gettext: MyApp.Gettext,
        statics: MyAppWeb.static_paths()

  Only `:gettext` is consumed here; every other option is passed through
  to `Phoenix.VerifiedRoutes` unchanged. Keep whatever the generated
  `MyAppWeb.verified_routes/0` already passed — in particular `:statics`,
  without which `~p"/images/logo.svg"` and the other asset paths in the
  default layouts warn that no route matches them.

  When configured, the sigil `~q` is made available to express localized verified routes. Sigil `~p` remains available for non-localized verified routes.

  The `~q` sigil generates a `case` statement that dispatches to the appropriate localized `~p` route based on the current locale:

      # ~q"/users" generates:
      case Localize.Routes.route_locale(Localize.get_locale(), [:de, :en, :fr]).cldr_locale_id do
        :de -> ~p"/benutzer"
        :en -> ~p"/users"
        :fr -> ~p"/utilisateurs"
      end

  A locale without localized routes, for example a supported locale that
  has no Gettext translations, gets the route of the default locale.

  ### Locale Interpolation

  A path may embed the current locale in one of its segments. Three
  tokens are recognised:

  * `locale` is replaced with the CLDR locale name.

  * `language` is replaced with the CLDR language code.

  * `territory` is replaced with the CLDR territory code.

  Each is written in one of two forms, and both resolve at compile time,
  once per locale branch:

      ~q"/\#{locale}/pages/intro"     # interpolation form
      ~q"/:locale/pages/intro"       # colon form

  The interpolation form looks like ordinary Elixir interpolation but is
  not — `locale` is a token recognised by the sigil, not a variable, and
  no binding of that name is consulted. It is the form to prefer, because
  it is the only one the `Localize.Routes.localize/1` macro accepts when
  defining routes: in a router, `:locale` is an ordinary Phoenix path
  parameter and is left alone.

      # in the router
      localize do
        get "/\#{locale}/pages/:page", PageController, :show
      end

      # in a template, matching that route
      ~q"/\#{locale}/pages/intro"

  The colon form is accepted in `~q` for convenience and has no router
  counterpart.

  ### Rendering a path or URL in a specific locale

  `sigil_q` dispatches on the *current* process locale set by
  `Localize.put_locale/1`. When you need to render a link in a different
  locale without changing the process locale — for example, emitting a
  language switcher that lists the same page in every configured locale —
  use `path_for/2` and `url_for/2`:

      # In a template, with @locale bound from the request or session:
      <.link href={path_for(@locale, "/users")}>Users</.link>

      # Render every configured locale in one pass (language switcher):
      for locale <- [:en, :fr, :de] do
        path_for(locale, "/users")
      end

      url_for(:fr, "/users")
      #=> "http://localhost/users_fr"

  """

  defmacro __using__(opts) do
    gettext = Keyword.fetch!(opts, :gettext)
    phoenix_opts = Keyword.drop(opts, [:gettext])

    quote location: :keep do
      use Phoenix.VerifiedRoutes, unquote(phoenix_opts)
      require unquote(gettext)

      import Phoenix.VerifiedRoutes, except: [url: 1, url: 2, url: 3]
      import Localize.VerifiedRoutes, only: :macros

      @_localize_gettext_backend unquote(gettext)
    end
  end

  @doc """
  Implements the `~q` sigil for localized verified routes.

  Generates a `case` expression that dispatches to the translated `~p` route for the current locale. The route path is verified at compile time against the router.

  """
  defmacro sigil_q({:<<>>, _meta, _segments} = route, flags) do
    locale_case(quote(do: Localize.get_locale()), route, flags, __CALLER__)
  end

  @doc """
  Generates the router url with localized route verification.

  """
  defmacro url({:sigil_q, _, [{:<<>>, _meta, _segments}, _flags]} = route) do
    expanded = Macro.expand(route, __CALLER__)
    wrap_sigil_p_in_url(expanded)
  end

  defmacro url(route) do
    quote do
      Phoenix.VerifiedRoutes.url(unquote(route))
    end
  end

  @doc """
  Generates the router url with localized route verification from the
  connection, socket, or URI.

  """
  defmacro url(
             conn_or_socket_or_endpoint_or_uri,
             {:sigil_q, _, [{:<<>>, _meta, _segments}, _]} = route
           ) do
    expanded = Macro.expand(route, __CALLER__)
    wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, expanded)
  end

  defmacro url(conn_or_socket_or_endpoint_or_uri, route) do
    quote do
      Phoenix.VerifiedRoutes.url(unquote(conn_or_socket_or_endpoint_or_uri), unquote(route))
    end
  end

  @doc """
  Generates the router url with localized route verification from the
  connection, socket, or URI and router.

  """
  defmacro url(
             conn_or_socket_or_endpoint_or_uri,
             router,
             {:sigil_q, _, [{:<<>>, _meta, _segments}, _]} = route
           ) do
    expanded = Macro.expand(route, __CALLER__)
    wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, router, expanded)
  end

  defmacro url(conn_or_socket_or_endpoint_or_uri, router, route) do
    quote do
      Phoenix.VerifiedRoutes.url(
        unquote(conn_or_socket_or_endpoint_or_uri),
        unquote(router),
        unquote(route)
      )
    end
  end

  @doc ~S'''
  Generates a localized verified path in a specific locale.

  Unlike `sigil_q/2`, which dispatches on the *current* locale
  (`Localize.get_locale/0`), `path_for/2` lets the caller force a particular
  locale at the call site without changing the process-wide locale. This is
  useful when rendering links in multiple locales within a single template
  (for example, a language switcher).

  ### Arguments

  * `locale` is a locale id (atom or string) or a `t:Localize.LanguageTag.t/0`,
    as a literal or a runtime expression. It is resolved like
    `Localize.validate_locale/1`, so with `de-CH` configured, `:de` and
    `"de-CH"` both select the German route. A locale without localized
    routes gets the route of the default locale.

  * `route` is a string literal route (with optional `#{...}` interpolations),
    as accepted by `sigil_q/2`.

  ### Examples

      path_for(:fr, "/users")
      #=> "/utilisateurs"

      for locale <- [:en, :fr] do
        {locale, path_for(locale, "/users")}
      end
      #=> [en: "/users", fr: "/utilisateurs"]

  '''
  defmacro path_for(locale, route) do
    locale_case(locale, normalize_route_ast(route), [], __CALLER__)
  end

  @doc ~S'''
  Generates a localized verified URL in a specific locale.

  Like `path_for/2` but returns a full URL via `Phoenix.VerifiedRoutes.url/1`.

  ### Arguments

  * `locale` is a locale as accepted by `path_for/2`.

  * `route` is a string literal route accepted by `sigil_q/2`.

  '''
  defmacro url_for(locale, route) do
    locale
    |> locale_case(normalize_route_ast(route), [], __CALLER__)
    |> wrap_sigil_p_in_url()
  end

  # Dispatches to the translated `~p` route of the locale that serves
  # `locale`, as chosen by `Localize.Routes.route_locale/2`.
  defp locale_case(locale, route, flags, caller) do
    gettext = Module.get_attribute(caller.module, :_localize_gettext_backend)
    locale_ids = Localize.Routes.locales_from_gettext(gettext)
    case_clauses = sigil_q_case_clauses(route, flags, locale_ids, gettext)

    quote location: :keep do
      case Localize.Routes.route_locale(unquote(locale), unquote(locale_ids)).cldr_locale_id do
        unquote(case_clauses)
      end
    end
  end

  @doc false
  # Normalises the second arg of `path_for/2`/`url_for/2`. Accepts either a
  # plain string literal (passed straight through the macro as a binary) or
  # an interpolated-string AST (`{:<<>>, _, _}`) and returns the AST shape
  # expected by `sigil_q_case_clauses/4`.
  def normalize_route_ast(route) when is_binary(route) do
    {:<<>>, [], [route]}
  end

  def normalize_route_ast({:<<>>, _, _} = ast), do: ast

  def normalize_route_ast(other) do
    raise ArgumentError,
          "path_for/2 and url_for/2 expect a string literal route " <>
            "(optionally with \#{...} interpolations); got: #{Macro.to_string(other)}"
  end

  @doc false
  def sigil_q_case_clauses(route, flags, locale_ids, gettext_backend) do
    for locale_id <- locale_ids do
      with {:ok, locale} <- Localize.validate_locale(locale_id),
           {:ok, _gettext_locale} <- Localize.Locale.gettext_locale_id(locale, gettext_backend) do
        translated_route =
          Localize.Routes.interpolate_and_translate_path(route, locale, gettext_backend)

        quote location: :keep do
          unquote(locale_id) -> sigil_p(unquote(translated_route), unquote(flags))
        end
      else
        {:error, _reason} ->
          IO.warn(
            "Locale #{inspect(locale_id)} has no associated gettext locale. " <>
              "Cannot translate #{inspect(route)}",
            []
          )

          nil
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&hd/1)
  end

  @doc false
  def wrap_sigil_p_in_url(ast) do
    Macro.postwalk(ast, fn
      {:->, meta, [locale, sigil_p]} ->
        url =
          quote do
            Phoenix.VerifiedRoutes.url(unquote(sigil_p))
          end

        {:->, meta, [locale, url]}

      other ->
        other
    end)
  end

  @doc false
  def wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, ast) do
    Macro.prewalk(ast, fn
      {:->, meta, [locale, sigil_p]} ->
        url =
          quote do
            Phoenix.VerifiedRoutes.url(
              unquote(conn_or_socket_or_endpoint_or_uri),
              unquote(sigil_p)
            )
          end

        {:->, meta, [locale, url]}

      other ->
        other
    end)
  end

  @doc false
  def wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, router, ast) do
    Macro.prewalk(ast, fn
      {:->, meta, [locale, sigil_p]} ->
        url =
          quote do
            Phoenix.VerifiedRoutes.url(
              unquote(conn_or_socket_or_endpoint_or_uri),
              unquote(router),
              unquote(sigil_p)
            )
          end

        {:->, meta, [locale, url]}

      other ->
        other
    end)
  end
end
