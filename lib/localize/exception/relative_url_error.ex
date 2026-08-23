defmodule Localize.RelativeUrlError do
  @moduledoc """
  Exception returned when an `hreflang` annotation is given a URL that is not
  fully qualified.

  Search engines and agents ignore `rel="alternate"` links whose `href` is
  relative, silently: the annotation is emitted, nothing consumes it, and the
  site appears not to declare the variant at all. Returning an error surfaces
  at development time what would otherwise be invisible in production.

  """

  defexception [:url, :locale]

  @typedoc """
  The offending URL and the locale it was annotating.

  """
  @type t :: %__MODULE__{url: String.t(), locale: String.t()}

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{url: url, locale: locale}) do
    "The hreflang URL #{inspect(url)} for locale #{inspect(locale)} is not fully qualified. " <>
      "An alternate link needs a scheme and host, such as \"https://example.com/de/page\"."
  end
end
