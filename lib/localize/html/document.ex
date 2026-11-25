defmodule Localize.HTML.Document do
  @moduledoc """
  The `lang` and `dir` attributes of a document for its locale.

  A page in Persian or Arabic is written right to left, and a screen reader chooses its voice from `lang`, so the `<html>` element of every page carries both. `attributes/1` returns them for a locale, taking the direction from CLDR's script data through `Localize.Locale.direction/1`, so no list of right-to-left languages needs to be kept.

  With Phoenix LiveView, two components use them:

  * `html/1` renders the `<html>` element of a root layout with `lang` and `dir`.

  * `live_locale/1` keeps them current across a live navigation. A root layout is rendered once per HTTP request, so a live navigation from an English page to a Persian one in the same live session leaves `<html lang="en" dir="ltr">`. Placed in the live view's layout, this element sets both on `<html>` whenever a page in another locale mounts, using `Phoenix.LiveView.JS` and no hook of your own. Localized routes made by `Localize.Routes.localize_live_session/3` do not need it, since a navigation to another locale there is a full page load.

  ### Examples

      # The root layout.
      <Localize.HTML.Document.html locale={@locale} class="h-full">
        <head>...</head>
        <body>{@inner_content}</body>
      </Localize.HTML.Document.html>

      # The live view's layout, for a live session whose pages change locale.
      <Localize.HTML.Document.live_locale locale={@locale} />

  """

  require Logger

  @doc """
  Returns the `lang` and `dir` attributes of a document in a locale.

  ### Arguments

  * `locale` is any locale `Localize.validate_locale/1` accepts. The default is `Localize.get_locale/0`.

  ### Returns

  * `{:ok, [lang: lang, dir: dir]}` where `lang` is the locale's canonical BCP 47 tag and `dir` is `"ltr"` or `"rtl"`, or

  * `{:error, exception}` when `locale` is not a valid locale.

  ### Examples

      iex> Localize.HTML.Document.attributes("fa")
      {:ok, [lang: "fa", dir: "rtl"]}

      iex> Localize.HTML.Document.attributes("es_MX")
      {:ok, [lang: "es-MX", dir: "ltr"]}

  """
  @spec attributes(Localize.locale() | Localize.LanguageTag.t()) ::
          {:ok, [lang: String.t(), dir: String.t()]} | {:error, Exception.t()}
  def attributes(locale \\ Localize.get_locale()) do
    with {:ok, tag} <- Localize.validate_locale(locale),
         {:ok, direction} <- Localize.Locale.direction(tag) do
      {:ok, [lang: to_string(tag.canonical_locale_id), dir: Atom.to_string(direction)]}
    end
  end

  if Code.ensure_loaded?(Phoenix.Component) do
    use Phoenix.Component

    alias Phoenix.LiveView.JS

    @doc """
    Renders the `<html>` element of a root layout with the `lang` and `dir` of a locale.

    A locale that is not valid is logged and the element is rendered without them, so a page still renders.

    ### Attributes

    * `:locale` is the page's locale. The default is `Localize.get_locale/0`.

    * Any other attribute, such as `class`, is rendered on the element.

    ### Examples

        <Localize.HTML.Document.html locale={@locale} class="h-full">
          <body>{@inner_content}</body>
        </Localize.HTML.Document.html>

    """
    attr(:locale, :any, default: nil, doc: "The page's locale; the current locale by default.")
    attr(:rest, :global)
    slot(:inner_block, required: true)

    @spec html(map()) :: Phoenix.LiveView.Rendered.t()
    def html(assigns) do
      assigns = assign(assigns, :document, document_attributes(assigns.locale, "html/1"))

      ~H"""
      <html {@document} {@rest}>{render_slot(@inner_block)}</html>
      """
    end

    @doc """
    Renders a hidden element that sets the `lang` and `dir` of `<html>` when a page mounts.

    Its id names the locale, so a live navigation to a page in another locale replaces the element and the attributes are set again. A locale that is not valid is logged and nothing is rendered.

    ### Attributes

    * `:locale` is the page's locale. The default is `Localize.get_locale/0`.

    ### Examples

        <Localize.HTML.Document.live_locale locale={@locale} />

    """
    attr(:locale, :any, default: nil, doc: "The page's locale; the current locale by default.")

    @spec live_locale(map()) :: Phoenix.LiveView.Rendered.t()
    def live_locale(assigns) do
      case document_attributes(assigns.locale, "live_locale/1") do
        [lang: lang, dir: dir] ->
          assigns =
            assign(assigns,
              id: "localize-document-" <> lang,
              set:
                JS.set_attribute({"lang", lang}, to: "html")
                |> JS.set_attribute({"dir", dir}, to: "html")
            )

          ~H"""
          <div id={@id} hidden phx-mounted={@set}></div>
          """

        [] ->
          ~H""
      end
    end

    defp document_attributes(nil, component) do
      document_attributes(Localize.get_locale(), component)
    end

    defp document_attributes(locale, component) do
      case attributes(locale) do
        {:ok, attributes} ->
          attributes

        {:error, exception} ->
          Logger.warning(
            "Localize.HTML.Document.#{component}: #{Exception.message(exception)}. " <>
              "No lang or dir attribute is rendered."
          )

          []
      end
    end
  end
end
