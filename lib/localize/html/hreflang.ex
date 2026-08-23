defmodule Localize.HTML.Hreflang do
  @moduledoc """
  Generates `rel="alternate"` `hreflang` annotations.

  An `hreflang` set is how a site tells search engines and agents which
  locale-specific variants of a page exist, and it is consumed rather than
  negotiated: nothing sends `Accept-Language` on the reader's behalf, so the
  declaration is the only signal.

  Which is why it is validated here rather than emitted verbatim. A malformed
  annotation is *silently* ignored by every consumer, so the failure never
  shows up in production — the site simply looks monolingual. Every locale is
  therefore validated and rendered in its canonical BCP 47 form, and every URL
  must be fully qualified.

  """

  alias Localize.RelativeUrlError

  # The hreflang spec reserves this for the page shown to readers whose locale
  # matches nothing else. It is not a language tag and must not be
  # canonicalised: Localize parses it as a private-use subtag and returns
  # "-x-default".
  @x_default "x-default"

  @doc """
  Builds `link` tags for a map of locale to URL.

  ### Arguments

  * `alternates` is a map of locale to fully-qualified URL. A locale may be
    any term `Localize.validate_locale/1` accepts, or the string `"x-default"`
    to designate the fallback variant.

  * `options` is a keyword list of options.

  ### Options

  * `:canonicalize` determines whether locales are rendered in canonical BCP 47
    form — `"es_MX"` becomes `"es-MX"`, `"en-us"` becomes `"en-US"`. The
    default is `true`. Set it to `false` to emit exactly what was supplied.

  ### Returns

  * `{:ok, safe}` where `safe` is rendered HTML, or

  * `{:error, exception}` if a locale is not recognised or a URL is not fully
    qualified.

  ### Examples

      iex> {:ok, {:safe, html}} = Localize.HTML.Hreflang.links(%{
      ...>   "en" => "https://example.com/",
      ...>   "de" => "https://example.com/de/"
      ...> })
      iex> IO.iodata_to_binary(html) =~ ~s|hreflang="de"|
      true

      # Underscores are canonicalised; BCP 47 requires a hyphen
      iex> {:ok, {:safe, html}} = Localize.HTML.Hreflang.links(%{"es_MX" => "https://example.com/mx/"})
      iex> IO.iodata_to_binary(html) =~ ~s|hreflang="es-MX"|
      true

      # A locale that does not exist is an error, not silent bad markup
      iex> Localize.HTML.Hreflang.links(%{"es-SP" => "https://example.com/es/"})
      {:error, %Localize.InvalidLocaleError{locale_id: "es-SP"}}

      # So is a relative URL, which every consumer ignores
      iex> {:error, error} = Localize.HTML.Hreflang.links(%{"de" => "/de/"})
      iex> error.__struct__
      Localize.RelativeUrlError

  """
  @spec links(map() | nil, keyword()) :: {:ok, Phoenix.HTML.safe()} | {:error, Exception.t()}
  def links(alternates, options \\ [])

  def links(nil, _options), do: {:ok, {:safe, []}}

  def links(alternates, options) when is_map(alternates) do
    canonicalize? = Keyword.get(options, :canonicalize, true)

    # Sorted so the rendered output is stable across runs, with x-default last
    # because it is the fallback rather than one of the alternatives.
    alternates
    |> Enum.sort_by(fn {locale, _url} -> {locale == @x_default, to_string(locale)} end)
    |> Enum.reduce_while([], fn {locale, url}, acc ->
      case tag(locale, url, canonicalize?) do
        {:ok, tag} -> {:cont, [tag | acc]}
        {:error, exception} -> {:halt, {:error, exception}}
      end
    end)
    |> case do
      {:error, exception} -> {:error, exception}
      tags -> {:ok, {:safe, tags |> Enum.reverse() |> Enum.intersperse(?\n)}}
    end
  end

  defp tag(locale, url, canonicalize?) do
    with {:ok, hreflang} <- hreflang(locale, canonicalize?),
         {:ok, url} <- qualified_url(url, hreflang) do
      {:safe, tag} =
        PhoenixHTMLHelpers.Tag.tag(:link, href: url, rel: "alternate", hreflang: hreflang)

      {:ok, tag}
    end
  end

  defp hreflang(locale, canonicalize?) do
    cond do
      to_string(locale) == @x_default -> {:ok, @x_default}
      not canonicalize? -> validated(locale, to_string(locale))
      true -> canonical(locale)
    end
  end

  # Validation alone is not enough. `"es_MX"` validates — Localize accepts the
  # POSIX spelling — but BCP 47, and therefore hreflang, requires a hyphen.
  defp canonical(locale) do
    case Localize.validate_locale(locale) do
      {:ok, validated} -> {:ok, to_string(validated.canonical_locale_id)}
      {:error, exception} -> {:error, exception}
    end
  end

  defp validated(locale, rendered) do
    case Localize.validate_locale(locale) do
      {:ok, _validated} -> {:ok, rendered}
      {:error, exception} -> {:error, exception}
    end
  end

  defp qualified_url(url, locale) do
    case URI.parse(to_string(url)) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, to_string(url)}

      _relative ->
        {:error, RelativeUrlError.exception(url: to_string(url), locale: locale)}
    end
  end
end
