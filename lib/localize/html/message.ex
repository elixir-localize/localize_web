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

    Unknown markup names raise `Localize.HTML.Message.UnknownMarkupError`
    at render time.

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
        walk_outputs(
          assigns.msgid,
          assigns.bindings,
          assigns.locale,
          assigns.components
        )

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
    """
    @spec render_to_safe(String.t(), map() | keyword(), keyword()) :: HTML.safe()
    def render_to_safe(msgid, bindings, options \\ []) do
      outputs =
        walk_outputs(
          msgid,
          bindings,
          Keyword.get(options, :locale),
          Keyword.get(options, :components, %{})
        )

      {:safe, Enum.map(outputs, &HTML.Safe.to_iodata/1)}
    end

    defp walk_outputs(msgid, bindings, locale, per_call_components) do
      components = resolve_components(per_call_components)

      format_options =
        [locale: locale]
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      case Localize.Message.format_to_safe_list(msgid, bindings, format_options) do
        {:ok, nodes} -> Enum.map(nodes, &walk_node(&1, components))
        {:error, exception} -> raise exception
      end
    end

    # Walk a tree node into a Safe value suitable for HEEx interpolation:
    # either a `Phoenix.LiveView.Rendered.t()` (preferred) or
    # `{:safe, iodata}`. Text nodes are HTML-escaped; markup nodes are
    # dispatched to a renderer.
    defp walk_node({:text, text}, _components) do
      HTML.html_escape(text)
    end

    defp walk_node({:markup, name, attrs, children}, components) do
      case Map.fetch(components, name) do
        {:ok, renderer} ->
          rendered_children =
            children
            |> Enum.map(&walk_node(&1, components))
            |> safe_concat()

          renderer.(%{attrs: attrs, children: rendered_children})

        :error ->
          raise UnknownMarkupError, tag: name, known: components |> Map.keys() |> Enum.sort()
      end
    end

    # Concatenate a list of mixed Rendered/{:safe, iodata} values into
    # a single {:safe, iodata} that renderers can interpolate as
    # already-escaped children.
    defp safe_concat(values) do
      iodata = Enum.map(values, &HTML.Safe.to_iodata/1)
      {:safe, iodata}
    end

    defp resolve_components(per_call) do
      app_components =
        :localize_web
        |> Application.get_env(:mf2_markup, [])
        |> Keyword.get(:components, %{})

      default_components()
      |> Map.merge(app_components)
      |> Map.merge(per_call)
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
