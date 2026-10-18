defmodule Localize.AcceptLanguage do
  @moduledoc """
  Parses HTTP `Accept-Language` headers and finds the best matching locale.

  The `Accept-Language` header is parsed per [RFC 2616](https://www.rfc-editor.org/rfc/rfc2616#section-14.4) into quality-tagged language tags which are then matched against the supported locales. The primary entry point is `best_match/1` which returns the highest-quality tag that matches a supported locale.

  """

  @doc """
  Tokenizes an `Accept-Language` header string into a list of
  `{quality, language_tag_string}` tuples sorted by quality descending.

  ### Arguments

  * `header` is an Accept-Language header string.

  ### Returns

  * A list of `{quality, language_tag_string}` tuples. A `header` that is not a string has no tags.

  ### Examples

      iex> Localize.AcceptLanguage.tokenize("en-US,en;q=0.9,fr;q=0.8")
      [{1.0, "en-us"}, {0.9, "en"}, {0.8, "fr"}]

  """
  @spec tokenize(term()) :: [{float(), String.t()}]
  def tokenize(header) when is_binary(header) do
    header
    |> String.downcase()
    |> String.replace(~r/\s/, "")
    |> String.split(",", trim: true)
    |> Enum.map(&parse_tag/1)
    |> Enum.reject(fn
      :invalid -> true
      {_quality, "*"} -> true
      {_quality, _tag} -> false
    end)
    |> Enum.sort_by(fn {quality, _tag} -> quality end, :desc)
  end

  def tokenize(_header), do: []

  @doc """
  Parses an `Accept-Language` header and validates each language tag
  against known locales.

  ### Arguments

  * `header` is an Accept-Language header string.

  ### Returns

  * `{:ok, [{quality, result}]}` where `result` is either
    `{:ok, Localize.LanguageTag.t()}` or `{:error, reason}`, or

  * `{:error, exception}` when `header` is not a string.

  ### Examples

      iex> {:ok, results} = Localize.AcceptLanguage.parse("en-US,zh;q=0.8")
      iex> length(results)
      2

  """
  @spec parse(term()) ::
          {:ok, [{float(), {:ok, Localize.LanguageTag.t()} | {:error, term()}}]}
          | {:error, Exception.t()}
  def parse(header) when is_binary(header) do
    results =
      header
      |> tokenize()
      |> Enum.map(fn {quality, tag} ->
        {quality, Localize.validate_locale(tag)}
      end)

    {:ok, results}
  end

  def parse(header), do: {:error, invalid_header(header)}

  @doc """
  Returns the best matching locale for the given `Accept-Language` header.

  Parses the header and returns the highest-quality language tag that
  matches a supported locale. A tag that only resolves to a supported
  locale by fallback, such as `ja` when no Japanese locale is supported,
  is skipped in favour of the next tag in the header.

  ### Arguments

  * `header` is an Accept-Language header string.

  ### Returns

  * `{:ok, Localize.LanguageTag.t()}` or

  * `{:error, exception}`: a `Localize.UnknownLocaleError` when no tag matches a supported locale, or a `Localize.InvalidValueError` when `header` is not a string.

  ### Examples

      iex> {:ok, locale} = Localize.AcceptLanguage.best_match("en-US,fr;q=0.8")
      iex> locale.language
      "en"

  """
  @spec best_match(term()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Exception.t()}
  def best_match(header) when is_binary(header) do
    result =
      header
      |> tokenize()
      |> Enum.find_value(fn {_quality, tag} -> supported_match(tag) end)

    case result do
      %Localize.LanguageTag{} = locale ->
        {:ok, locale}

      nil ->
        {:error, Localize.UnknownLocaleError.exception(locale_id: header)}
    end
  end

  def best_match(header), do: {:error, invalid_header(header)}

  defp invalid_header(header) do
    Localize.InvalidValueError.exception(
      value: header,
      expected: "an Accept-Language header string"
    )
  end

  # `Localize.validate_locale/1` never rejects a valid tag: with no close
  # supported locale it falls back to the first one (`ja` resolves to
  # `de-CH` data when only `de-CH` and `en-CH` are supported). A distance
  # of 80 means unrelated languages, so a match within 79 keeps every
  # CLDR match (`en-US` to `en-CH`, `gsw` to `de-CH`) and skips the
  # fallback. When CLDR matches across languages, the supported locale
  # is returned, so its language is the one being served.
  @max_match_distance 79

  defp supported_match(tag) do
    with {:ok, requested} <- Localize.validate_locale(tag),
         {:ok, locale_id, _distance} <-
           Localize.LanguageTag.best_match(
             requested,
             [requested.cldr_locale_id],
             @max_match_distance
           ),
         {:ok, served} <- Localize.validate_locale(locale_id) do
      if served.language == requested.language, do: requested, else: served
    else
      _no_match -> nil
    end
  end

  # Split on the `;q=` weight parameter. A well-formed tag has at most one
  # weight, but real-world Accept-Language headers sometimes contain
  # duplicates (e.g. `"ja;q=0.9;q=0.9"`). Per RFC 9110 §5.3 duplicates are
  # invalid, but a lenient parser takes the first weight and ignores the
  # rest rather than crashing.
  defp parse_tag(segment) do
    case String.split(segment, ";q=") do
      [tag] ->
        {1.0, tag}

      [tag, quality | _extra] ->
        case Float.parse(quality) do
          {q, _rest} when q > 0.0 and q <= 1.0 -> {q, tag}
          _invalid -> :invalid
        end
    end
  end
end
