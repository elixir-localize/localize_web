if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Localize.HTML.Message do
    @moduledoc """
    Renders an ICU MessageFormat 2 message into HEEx, including any
    MF2 markup tags.

    MF2 supports inline markup of the form `{#name attr=value}…{/name}`
    (paired) and `{#name/}` (standalone). `Localize.Message.format/3`
    strips these tags. This component preserves them by walking the
    structured output of `Localize.Message.format_to_safe_list/3` and
    dispatching each markup node to a registered renderer.

    ## Example

        <.message msgid={~t"Read our {#link href=|/terms|}terms{/link}"} />

    The msgid attribute typically comes from `~t` (which performs the
    Gettext lookup and binding interpolation), but any MF2 string is
    accepted.

    ## Component registry

    Markup names map to renderer functions. Three sources are consulted
    in order:

    1. The `:components` attribute on the component, if provided.

    2. The `:components` key under `config :localize_web, :mf2_markup`.

    3. The built-in defaults: `bold`/`strong` → `<strong>`,
       `italic`/`emphasis`/`em` → `<em>`, `code` → `<code>`,
       `link` → `<.link>` (Phoenix component — accepts `href`,
       `navigate`, or `patch` MF2 attributes), `br` → `<br>`.

    Each renderer is a function of one argument
    `%{attrs: map, children: safe_iodata}` returning either
    `Phoenix.LiveView.Rendered.t()` (the recommended form, via `~H`)
    or a `Phoenix.HTML.safe()` value (`{:safe, iodata}`). The `children`
    value is already rendered and HTML-escaped — wrap or ignore it,
    but do not pass it through `Phoenix.HTML.html_escape/1` again.

    The component never raises, since a message is rendered on every
    page that shows it. An unknown markup name logs a warning and renders
    the tag's children without it. A message that cannot be formatted,
    such as one with invalid MF2 syntax or unbalanced markup, logs a
    warning and renders its source text, escaped. `render_to_safe/3`
    returns `{:error, exception}` in both cases instead.

    ## Bindings and locale

    The `:bindings` attribute is forwarded to MF2 formatting. The
    `:locale` attribute overrides `Localize.get_locale/0` for this
    render only.

    """

    use Phoenix.Component

    alias Phoenix.HTML

    defmodule UnknownMarkupError do
      defexception [:tag, :known]

      def message(%{tag: tag, known: known}) do
        "unknown MF2 markup tag #{inspect(tag)} in message; " <>
          "known tags: #{Enum.map_join(known, ", ", &inspect/1)}. " <>
          "Pass `:components` to the <.message> component or configure " <>
          "`config :localize_web, :mf2_markup, components: %{…}` to register it."
      end
    end

    @doc """
    Renders an MF2 message preserving its inline markup structure.

    ### Attributes

    * `:msgid` — the MF2 message string. Required.

    * `:bindings` — a map of variable bindings for MF2 placeholders.
      The default is `%{}`.

    * `:locale` — a locale name or `t:Localize.LanguageTag.t/0`.
      The default is `Localize.get_locale/0`.

    * `:components` — a map of `%{markup_name => renderer_fun}` that
      overrides defaults and app config for this render only.
      The default is `%{}`.

    ### Returns

    * A HEEx-safe rendering of the message with markup nodes expanded
      and text nodes HTML-escaped.

    ### Examples

        <.message msgid="Hello {$name}!" bindings={%{"name" => "Kip"}} />
        <.message msgid={~t"Click {#link href=|/home|}here{/link}"} />

    """
    attr(:msgid, :string, required: true)
    attr(:bindings, :map, default: %{})
    attr(:locale, :any, default: nil)
    attr(:components, :map, default: %{})

    def message(assigns) do
      outputs =
        case walk_outputs(
               assigns.msgid,
               assigns.bindings,
               assigns.locale,
               assigns.components,
               :lenient
             ) do
          {:ok, outputs} ->
            outputs

          {:error, exception} ->
            log_render_error(exception, assigns.msgid)
            [HTML.html_escape(source_text(assigns.msgid))]
        end

      assigns = assign(assigns, :__outputs, outputs)

      ~H"""
      <%= for output <- @__outputs do %>{output}<% end %>
      """
    end

    @doc """
    Renders an MF2 message to a `Phoenix.HTML.safe()` value without
    going through HEEx. Useful for unit-testing markup output and for
    composing rendered messages into Phoenix.HTML pipelines.

    Accepts the same options as the component, passed as a keyword list.

    ### Returns

    * A `t:Phoenix.HTML.safe/0` value, or

    * `{:error, exception}` when the message cannot be formatted or uses
      an unknown markup name (`Localize.HTML.Message.UnknownMarkupError`).
    """
    @spec render_to_safe(String.t(), map() | keyword(), keyword()) ::
            HTML.safe() | {:error, Exception.t()}
    def render_to_safe(msgid, bindings, options \\ []) do
      with {:ok, options} <- keyword_options(options),
           {:ok, outputs} <-
             walk_outputs(
               msgid,
               bindings,
               Keyword.get(options, :locale),
               Keyword.get(options, :components, %{}),
               :strict
             ) do
        {:safe, Enum.map(outputs, &HTML.Safe.to_iodata/1)}
      end
    end

    defp keyword_options(options) do
      if Keyword.keyword?(options), do: {:ok, options}, else: invalid_options(options)
    end

    @doc false
    # The render path of `Localize.HTML.t/2`, which must not raise: an
    # unknown markup name renders its children, and a message that cannot
    # be rendered logs a warning and renders its source text, escaped.
    def render_to_safe_or_source(msgid, bindings, options) do
      result =
        with {:ok, options} <- keyword_options(options) do
          walk_outputs(
            msgid,
            bindings,
            Keyword.get(options, :locale),
            Keyword.get(options, :components, %{}),
            :lenient
          )
        end

      case result do
        {:ok, outputs} ->
          {:safe, Enum.map(outputs, &HTML.Safe.to_iodata/1)}

        {:error, exception} ->
          log_render_error(exception, msgid)
          HTML.html_escape(source_text(msgid))
      end
    end

    defp invalid_options(options) do
      {:error,
       Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")}
    end

    defp walk_outputs(msgid, bindings, locale, per_call_components, mode) do
      format_options =
        [locale: locale]
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      with {:ok, components} <- resolve_components(per_call_components),
           {:ok, nodes} <- format(msgid, bindings, format_options) do
        walk_nodes(nodes, components, mode)
      end
    end

    # `Localize.Message.format_to_safe_list/3` in Localize 1.3.0 raises for
    # bindings that are neither a map nor a keyword list. This is fixed on
    # Localize main; once that is on hex and required here, the bindings
    # check can go. See TODO.md.
    defp format(msgid, bindings, options) when is_binary(msgid) do
      if is_map(bindings) or (is_list(bindings) and Keyword.keyword?(bindings)) do
        Localize.Message.format_to_safe_list(msgid, bindings, options)
      else
        {:error,
         Localize.InvalidValueError.exception(
           value: bindings,
           expected: "a map or keyword list of bindings"
         )}
      end
    end

    defp format(msgid, _bindings, _options) do
      {:error,
       Localize.InvalidValueError.exception(value: msgid, expected: "an MF2 message string")}
    end

    defp walk_nodes(nodes, components, mode) do
      nodes
      |> Enum.reduce_while([], fn node, acc ->
        case walk_node(node, components, mode) do
          {:ok, output} -> {:cont, [output | acc]}
          {:error, exception} -> {:halt, {:error, exception}}
        end
      end)
      |> case do
        {:error, exception} -> {:error, exception}
        outputs -> {:ok, Enum.reverse(outputs)}
      end
    end

    # Walk a tree node into a Safe value suitable for HEEx interpolation:
    # either a `Phoenix.LiveView.Rendered.t()` (preferred) or
    # `{:safe, iodata}`. Text nodes are HTML-escaped; markup nodes are
    # dispatched to a renderer. In `:lenient` mode an unknown markup name
    # renders its children; in `:strict` mode it is an error.
    defp walk_node({:text, text}, _components, _mode) do
      {:ok, HTML.html_escape(text)}
    end

    defp walk_node({:markup, name, attrs, children}, components, mode) do
      with {:ok, rendered_children} <- walk_nodes(children, components, mode) do
        children = safe_concat(rendered_children)

        case {Map.fetch(components, name), mode} do
          {{:ok, renderer}, _mode} ->
            {:ok, renderer.(%{attrs: attrs, children: children})}

          {:error, :lenient} ->
            log_render_error(unknown_markup(name, components), nil)
            {:ok, children}

          {:error, :strict} ->
            {:error, unknown_markup(name, components)}
        end
      end
    end

    defp unknown_markup(name, components) do
      UnknownMarkupError.exception(tag: name, known: components |> Map.keys() |> Enum.sort())
    end

    defp source_text(msgid) when is_binary(msgid), do: msgid
    defp source_text(_msgid), do: ""

    defp log_render_error(exception, msgid) do
      require Logger

      message =
        if msgid,
          do: "#{Exception.message(exception)} in message #{inspect(msgid)}",
          else: Exception.message(exception)

      Logger.warning("Localize.HTML.Message: " <> message)
    end

    # Concatenate a list of mixed Rendered/{:safe, iodata} values into
    # a single {:safe, iodata} that renderers can interpolate as
    # already-escaped children.
    defp safe_concat(values) do
      iodata = Enum.map(values, &HTML.Safe.to_iodata/1)
      {:safe, iodata}
    end

    defp resolve_components(per_call) when is_map(per_call) do
      app_components =
        :localize_web
        |> Application.get_env(:mf2_markup, [])
        |> Keyword.get(:components, %{})

      {:ok,
       default_components()
       |> Map.merge(app_components)
       |> Map.merge(per_call)}
    end

    defp resolve_components(per_call) do
      {:error,
       Localize.InvalidValueError.exception(
         value: per_call,
         expected: "a map of markup names to renderer functions"
       )}
    end

    @doc """
    Returns the built-in markup component map.

    Exposed so apps can selectively reuse defaults when building a
    custom registry, e.g.:

        config :localize_web, :mf2_markup,
          components: Map.merge(
            Localize.HTML.Message.default_components(),
            %{"user" => &MyAppWeb.MF2.user/1}
          )

    """
    @spec default_components() :: %{String.t() => (map() -> Phoenix.LiveView.Rendered.t())}
    def default_components do
      %{
        "bold" => &render_strong/1,
        "strong" => &render_strong/1,
        "italic" => &render_em/1,
        "emphasis" => &render_em/1,
        "em" => &render_em/1,
        "code" => &render_code/1,
        "link" => &render_link/1,
        "br" => &render_br/1
      }
    end

    defp render_strong(%{children: children}) do
      assigns = %{children: children}
      ~H"<strong>{@children}</strong>"
    end

    defp render_em(%{children: children}) do
      assigns = %{children: children}
      ~H"<em>{@children}</em>"
    end

    defp render_code(%{children: children}) do
      assigns = %{children: children}
      ~H"<code>{@children}</code>"
    end

    # MF2 `link` markup maps to Phoenix's `<.link>` component. The
    # caller may use any of `href`, `navigate`, or `patch` as the MF2
    # attribute; this lets translators emit verified-route paths and
    # LiveView-aware navigation links from a `.po` file.
    defp render_link(%{attrs: attrs, children: children}) do
      assigns = %{
        href: Map.get(attrs, "href"),
        navigate: Map.get(attrs, "navigate"),
        patch: Map.get(attrs, "patch"),
        children: children
      }

      ~H"""
      <.link
        :if={@navigate}
        navigate={@navigate}
      >{@children}</.link><.link
        :if={!@navigate && @patch}
        patch={@patch}
      >{@children}</.link><.link
        :if={!@navigate && !@patch}
        href={@href || "#"}
      >{@children}</.link>
      """
    end

    defp render_br(_payload) do
      assigns = %{}
      ~H"<br />"
    end
  end
end
