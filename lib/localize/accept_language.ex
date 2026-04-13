defmodule Localize.AcceptLanguage do
  @moduledoc """
  Parses HTTP `Accept-Language` headers and finds the best matching locale.

  The `Accept-Language` header is parsed per [RFC 2616](https://www.rfc-editor.org/rfc/rfc2616#section-14.4) into quality-tagged language tags which are then matched against available locales using `Localize.validate_locale/1`. The primary entry point is `best_match/1` which returns the highest-quality successfully validated locale.

  """

  @doc """
  Tokenizes an `Accept-Language` header string into a list of
  `{quality, language_tag_string}` tuples sorted by quality descending.

  ### Arguments

  * `header` is an Accept-Language header string.

  ### Returns

  * A list of `{quality, language_tag_string}` tuples.

  ### Examples

      iex> Localize.AcceptLanguage.tokenize("en-US,en;q=0.9,fr;q=0.8")
      [{1.0, "en-us"}, {0.9, "en"}, {0.8, "fr"}]

  """
  @spec tokenize(String.t()) :: [{float(), String.t()}]
  def tokenize(header) when is_binary(header) do
    header
    |> String.downcase()
    |> String.replace(~r/\s/, "")
    |> String.split(",", trim: true)
    |> Enum.map(&parse_tag/1)
    |> Enum.reject(fn {_quality, tag} -> tag == "*" end)
    |> Enum.sort_by(fn {quality, _tag} -> quality end, :desc)
  end

  @doc """
  Parses an `Accept-Language` header and validates each language tag
  against known locales.

  ### Arguments

  * `header` is an Accept-Language header string.

  ### Returns

  * `{:ok, [{quality, result}]}` where `result` is either
    `{:ok, Localize.LanguageTag.t()}` or `{:error, reason}`.

  ### Examples

      iex> {:ok, results} = Localize.AcceptLanguage.parse("en-US,zh;q=0.8")
      iex> length(results)
      2

  """
  @spec parse(String.t()) ::
          {:ok, [{float(), {:ok, Localize.LanguageTag.t()} | {:error, term()}}]}
  def parse(header) when is_binary(header) do
    results =
      header
      |> tokenize()
      |> Enum.map(fn {quality, tag} ->
        {quality, Localize.validate_locale(tag)}
      end)

    {:ok, results}
  end

  @doc """
  Returns the best matching locale for the given `Accept-Language` header.

  Parses the header, validates each language tag, and returns the
  highest-quality successfully validated locale.

  ### Arguments

  * `header` is an Accept-Language header string.

  ### Returns

  * `{:ok, Localize.LanguageTag.t()}` or

  * `{:error, Localize.NoMatchingLocaleError.t()}`

  ### Examples

      iex> {:ok, locale} = Localize.AcceptLanguage.best_match("en-US,fr;q=0.8")
      iex> locale.language
      "en"

  """
  @spec best_match(String.t()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Localize.UnknownLocaleError.t()}
  def best_match(header) when is_binary(header) do
    result =
      header
      |> tokenize()
      |> Enum.find_value(fn {_quality, tag} ->
        case Localize.validate_locale(tag) do
          {:ok, %Localize.LanguageTag{cldr_locale_id: id} = locale} when not is_nil(id) ->
            locale

          _other ->
            nil
        end
      end)

    case result do
      %Localize.LanguageTag{} = locale ->
        {:ok, locale}

      nil ->
        {:error, Localize.UnknownLocaleError.exception(locale_id: header)}
    end
  end

  defp parse_tag(segment) do
    case String.split(segment, ";q=") do
      [tag, quality] ->
        case Float.parse(quality) do
          {q, _} -> {q, tag}
          :error -> {1.0, tag}
        end

      [tag] ->
        {1.0, tag}
    end
  end
end
