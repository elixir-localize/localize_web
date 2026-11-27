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

      # ~q"/users" generates, where `route_locales` are the language tags
      # of the Gettext locales :de, :en and :fr:
      case Localize.Routes.route_locale(Localize.get_locale(), route_locales).cldr_locale_id do
        :de -> ~p"/benutzer"
        :en -> ~p"/users"
        :fr -> ~p"/utilisateurs"
      end

  A locale without localized routes, for example a supported locale that
  has no Gettext translations, gets the route of the default locale, as
  does an invalid locale. If the default locale has no localized routes
  either, the first locale that has them is used, so rendering a link
  never raises.

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
  use `path_for/3` and `url_for/3`:

      # In a template, with @locale bound from the request or session:
      <.link href={path_for(@locale, "/users")}>Users</.link>

      # Render every configured locale in one pass (language switcher):
      for locale <- [:en, :fr, :de] do
        path_for(locale, "/users")
      end

      url_for(:fr, "/users")
      #=> "http://localhost/users_fr"

  ### Routes declared for some locales only

  `~q` renders a route for every locale the Gettext backend has. A route
  declared inside `localize [:en, :fr]` in the router has no address in
  another locale, so for a third locale with translations `~q` would give a
  path that no route serves, and Phoenix warns of it at compile time. Link
  to such a route with `path_for/3` or `url_for/3` and the router's list as
  `:locales`: a locale outside it gets the default locale's route.

      path_for(Localize.get_locale(), "/comments", locales: [:en, :fr])

  The router's own helpers need no option: each knows the locales its
  routes were declared for.

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
    locale_case(quote(do: Localize.get_locale()), route, flags, [], __CALLER__)
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
  (`Localize.get_locale/0`), `path_for/3` lets the caller force a particular
  locale at the call site without changing the process-wide locale. This is
  useful when rendering links in multiple locales within a single template
  (for example, a language switcher).

  It is also the way to link to a route declared for some locales only,
  inside `localize [:en, :fr]` in the router: `sigil_q/2` renders a route
  for every Gettext locale, so another locale with translations would get a
  path that no route serves. Pass the router's list as `:locales`, with
  `Localize.get_locale/0` as the locale to dispatch on the current one.

  ### Arguments

  * `locale` is a locale id (atom or string) or a `t:Localize.LanguageTag.t/0`,
    as a literal or a runtime expression. It is resolved like
    `Localize.validate_locale/1`, so with `de-CH` configured, `:de` and
    `"de-CH"` both select the German route. A locale without localized
    routes, or an invalid locale, gets the route of the default locale.

  * `route` is a string literal route (with optional `#{...}` interpolations),
    as accepted by `sigil_q/2`.

  * `options` is a literal keyword list of options.

  ### Options

  * `:locales` is the literal list of locale ids the route is declared for,
    as given to `Localize.Routes.localize/2`. Only those locales get their
    own route; any other gets the route of the default locale, or of the
    first listed locale when the default is not listed. An invalid locale
    raises at compile time, and one without Gettext translations is warned
    of and skipped, as in the router. The default is every Gettext locale.

  ### Returns

  * The path, a string.

  ### Examples

      path_for(:fr, "/users")
      #=> "/utilisateurs"

      for locale <- [:en, :fr] do
        {locale, path_for(locale, "/users")}
      end
      #=> [en: "/users", fr: "/utilisateurs"]

      # A route declared inside `localize [:en, :fr]`, for the current locale
      path_for(Localize.get_locale(), "/comments", locales: [:en, :fr])
      #=> "/comments" when the current locale is :de

  '''
  defmacro path_for(locale, route, options \\ []) do
    locale_case(locale, normalize_route_ast(route), [], options, __CALLER__)
  end

  @doc ~S'''
  Generates `rel="alternate"` `hreflang` link tags for every configured locale.

  Renders `route` once per locale configured in the Gettext backend and
  annotates each with its locale, which is what tells a search engine or an
  agent that the variants exist. Nothing sends `Accept-Language` on a reader's
  behalf, so this declaration is the signal.

  Every locale is validated and rendered in canonical BCP 47 form, and every
  URL must be fully qualified — a malformed annotation is ignored silently by
  every consumer, so an error is returned rather than bad markup emitted. See
  `Localize.HTML.Hreflang.links/2`.

  ### Arguments

  * `route` is a string literal route accepted by `sigil_q/2`.

  * `options` is a keyword list of options. Any option but `:locales` is
    passed to `Localize.HTML.Hreflang.links/2`.

  ### Options

  * `:locales` is the literal list of locale ids the route is declared for,
    as for `path_for/3`. Only those locales are annotated. It is read only
    when `options` is a literal keyword list. The default is every Gettext
    locale.

  ### Returns

  * `{:ok, safe}` where `safe` is rendered HTML, or

  * `{:error, exception}`.

  ### Examples

      # In a template <head>
      <%= case hreflang_links("/users") do %>
        <% {:ok, links} -> %><%= links %>
        <% {:error, _} -> %>
      <% end %>

      # A route declared inside `localize [:en, :fr]`
      hreflang_links("/comments", locales: [:en, :fr])

  '''
  defmacro hreflang_links(route, options \\ []) do
    gettext = Module.get_attribute(__CALLER__.module, :_localize_gettext_backend)
    {route_options, options} = split_route_options(options)
    route_locales = route_locales(gettext, route_options)
    route_ast = Localize.VerifiedRoutes.normalize_route_ast(route)

    case_clauses =
      Localize.VerifiedRoutes.sigil_q_case_clauses(route_ast, [], route_locales, gettext)

    pairs =
      Enum.map(route_locales, fn %Localize.LanguageTag{cldr_locale_id: locale_id} ->
        case_expr =
          quote location: :keep do
            case unquote(locale_id) do
              unquote(case_clauses)
            end
          end

        {Kernel.to_string(locale_id), wrap_sigil_p_in_url(case_expr)}
      end)

    quote location: :keep do
      Localize.HTML.Hreflang.links(unquote({:%{}, [], pairs}), unquote(options))
    end
  end

  @doc ~S'''
  Generates a localized verified URL in a specific locale.

  Like `path_for/3` but returns a full URL via `Phoenix.VerifiedRoutes.url/1`.

  ### Arguments

  * `locale` is a locale as accepted by `path_for/3`.

  * `route` is a string literal route accepted by `sigil_q/2`.

  * `options` is a literal keyword list of options.

  ### Options

  * `:locales` is the literal list of locale ids the route is declared for,
    as for `path_for/3`.

  ### Returns

  * The URL, a string.

  ### Examples

      url_for(:fr, "/users")
      #=> "http://localhost/utilisateurs"

      url_for(:de, "/comments", locales: [:en, :fr])
      #=> "http://localhost/comments"

  '''
  defmacro url_for(locale, route, options \\ []) do
    locale
    |> locale_case(normalize_route_ast(route), [], options, __CALLER__)
    |> wrap_sigil_p_in_url()
  end

  # Dispatches to the translated `~p` route of the locale that serves
  # `locale`, as chosen by `Localize.Routes.route_locale/2`, among the
  # locales the route is declared for: every Gettext locale, or those of
  # the `:locales` option.
  defp locale_case(locale, route, flags, options, caller) do
    gettext = Module.get_attribute(caller.module, :_localize_gettext_backend)
    route_locales = route_locales(gettext, options)
    case_clauses = sigil_q_case_clauses(route, flags, route_locales, gettext)

    quote location: :keep do
      case Localize.Routes.route_locale(unquote(locale), unquote(Macro.escape(route_locales))).cldr_locale_id do
        unquote(case_clauses)
      end
    end
  end

  # The locales a route is declared for, in the order of the Gettext
  # locales. A `:locales` option is a literal list resolved as
  # `Localize.Routes.localize/2` resolves its own, so the list a router
  # declares a route for can be copied here: an invalid locale raises at
  # compile time, and one without Gettext translations is warned of and
  # skipped.
  defp route_locales(gettext, options) do
    gettext_locales = Localize.Routes.locales_from_gettext(gettext)

    case Keyword.fetch(literal_options(options), :locales) do
      {:ok, locale_ids} -> declared_locales(locale_ids, gettext_locales)
      :error -> gettext_locales
    end
  end

  # `hreflang_links/2` passes its options on to `Localize.HTML.Hreflang.links/2`
  # and may be given them as an expression; `:locales` is read only from a
  # literal keyword list.
  defp split_route_options(options) do
    if Keyword.keyword?(options) do
      Keyword.split(options, [:locales])
    else
      {[], options}
    end
  end

  defp literal_options(options) do
    if Keyword.keyword?(options) do
      options
    else
      raise ArgumentError,
            "expected the options to be a literal keyword list; got: #{Macro.to_string(options)}"
    end
  end

  defp declared_locales([_ | _] = locale_ids, gettext_locales) do
    declared_ids = Enum.flat_map(locale_ids, &declared_locale_id(&1, gettext_locales))

    case Enum.filter(gettext_locales, &(&1.cldr_locale_id in declared_ids)) do
      [] -> raise ArgumentError, "none of the locales #{inspect(locale_ids)} has localized routes"
      [_ | _] = route_locales -> route_locales
    end
  end

  defp declared_locales(locale_ids, _gettext_locales) do
    raise ArgumentError,
          "expected :locales to be a non-empty literal list of locale ids; got: " <>
            Macro.to_string(locale_ids)
  end

  defp declared_locale_id(locale_id, gettext_locales)
       when is_atom(locale_id) or is_binary(locale_id) do
    case Localize.validate_locale(locale_id) do
      {:ok, %Localize.LanguageTag{cldr_locale_id: id}} ->
        gettext_locale_id(id, locale_id, gettext_locales)

      {:error, exception} ->
        raise exception
    end
  end

  defp declared_locale_id(locale_id, _gettext_locales) do
    raise ArgumentError,
          "expected :locales to hold locale ids as atoms or strings; got: " <>
            Macro.to_string(locale_id)
  end

  defp gettext_locale_id(id, locale_id, gettext_locales) do
    if Enum.any?(gettext_locales, &(&1.cldr_locale_id == id)) do
      [id]
    else
      IO.warn(
        "Locale #{inspect(locale_id)} has no associated gettext locale and has no localized routes",
        []
      )

      []
    end
  end

  @doc false
  # Normalises the second arg of `path_for/3`/`url_for/3`. Accepts either a
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
  # One `case` clause for each locale in `route_locales`, the tags
  # `Localize.Routes.locales_from_gettext/1` gives, keyed by locale id.
  def sigil_q_case_clauses(route, flags, route_locales, gettext_backend) do
    Enum.flat_map(route_locales, &sigil_q_case_clause(route, flags, &1, gettext_backend))
  end

  defp sigil_q_case_clause(route, flags, locale, gettext_backend) do
    case Localize.Locale.gettext_locale_id(locale, gettext_backend) do
      {:ok, _gettext_locale} ->
        translated_route =
          Localize.Routes.interpolate_and_translate_path(route, locale, gettext_backend)

        quote location: :keep do
          unquote(locale.cldr_locale_id) -> sigil_p(unquote(translated_route), unquote(flags))
        end

      {:error, _reason} ->
        IO.warn(
          "Locale #{inspect(locale.cldr_locale_id)} has no associated gettext locale. " <>
            "Cannot translate #{inspect(route)}",
          []
        )

        []
    end
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
