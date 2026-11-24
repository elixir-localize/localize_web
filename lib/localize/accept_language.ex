defmodule Localize.AcceptLanguage do
  @moduledoc """
  Parses HTTP `Accept-Language` headers and finds the best matching locale.

  The `Accept-Language` header is parsed per [RFC 2616](https://www.rfc-editor.org/rfc/rfc2616#section-14.4) into quality-tagged language tags which are then matched against the supported locales. The primary entry point is `best_match/2` which returns the highest-quality tag that matches a supported locale: one configured for Localize, or one in a list given with the `:supported` option.

  """

  # `Localize.validate_locale/1` never rejects a valid tag: with no close
  # supported locale it falls back to the first one (`ja` resolves to
  # `de-CH` data when only `de-CH` and `en-CH` are supported). A distance
  # of 80 means unrelated languages, so a match within 79 keeps every
  # CLDR match (`en-US` to `en-CH`, `gsw` to `de-CH`) and skips the
  # fallback.
  @max_match_distance 79

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

  * `options` is a keyword list of options.

  ### Options

  * `:supported` is the list of locales to match against, for an
    application whose locales are known only at runtime, such as a site
    whose languages are kept in a database. Each entry is a locale
    identifier string or atom, or a `t:Localize.LanguageTag.t/0`, and
    should be a locale Localize is configured for, or its data falls
    back to another locale. The locale returned is the entry that
    matched, so `en-AU` matched against `["en", "de"]` returns `en`.
    The default is the locales configured for Localize, and the locale
    returned is then the one the header asked for.

  ### Returns

  * `{:ok, Localize.LanguageTag.t()}` or

  * `{:error, exception}`: a `Localize.UnknownLocaleError` when no tag matches a supported locale, or a `Localize.InvalidValueError` when `header` is not a string or `:supported` is not a list.

  ### Examples

      iex> {:ok, locale} = Localize.AcceptLanguage.best_match("en-US,fr;q=0.8")
      iex> locale.language
      :en

      iex> {:ok, locale} = Localize.AcceptLanguage.best_match("de-CH,fr;q=0.8", supported: ["en", "fr"])
      iex> locale.cldr_locale_id
      :fr

  """
  @spec best_match(term(), Keyword.t()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Exception.t()}
  def best_match(header, options \\ [])

  def best_match(header, options) when is_binary(header) and is_list(options) do
    with {:ok, supported} <- supported_option(options) do
      no_match = {:error, Localize.UnknownLocaleError.exception(locale_id: header)}

      header
      |> tokenize()
      |> Enum.find_value(no_match, fn {_quality, tag} ->
        matched(supported_match(tag, supported))
      end)
    end
  end

  def best_match(header, options) when is_list(options) do
    {:error, invalid_header(header)}
  end

  def best_match(_header, options) do
    {:error, invalid_options(options)}
  end

  defp invalid_header(header) do
    Localize.InvalidValueError.exception(
      value: header,
      expected: "an Accept-Language header string"
    )
  end

  defp invalid_options(options) do
    Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")
  end

  defp supported_option(options) do
    case Keyword.get(options, :supported) do
      nil ->
        {:ok, nil}

      supported when is_list(supported) ->
        {:ok, supported}

      other ->
        {:error,
         Localize.InvalidValueError.exception(
           value: other,
           expected: "a list of locales for the :supported option"
         )}
    end
  end

  # A tag's supported locale, when it matches one within
  # `@max_match_distance`.
  #
  # With no list of supported locales, the tag is matched against the
  # locale Localize resolved it to among the configured ones. When CLDR
  # matches across languages, the supported locale is returned, so its
  # language is the one being served.
  #
  # With a list, the entry that matched is returned, validated, so the
  # caller learns which of its own locales was chosen.
  #
  # `Localize.Plug.PutLocale` applies the same test to an identifier in the
  # URL, a form, a cookie, the session or the host, so that the header and
  # the other sources agree on what counts as a locale the application
  # supports.
  @doc false
  def supported_match(tag, nil) do
    with {:ok, requested} <- Localize.validate_locale(tag),
         {:ok, locale_id, _distance} <-
           Localize.LanguageTag.best_match(
             requested,
             [requested.cldr_locale_id],
             @max_match_distance
           ),
         {:ok, served} <- Localize.validate_locale(locale_id) do
      {:ok, if(served.language == requested.language, do: requested, else: served)}
    end
  end

  def supported_match(tag, supported) when is_list(supported) do
    with {:ok, requested} <- Localize.validate_locale(tag),
         {:ok, entry} <- closest_supported(requested, supported) do
      served_locale(entry)
    end
  end

  # The tag is matched by its canonical identifier: validation fills in the
  # likely subtags, and the root locale's are `en-Latn-US`, so the tag
  # itself would match `und` as English. `Localize.LanguageTag.best_match/3`
  # answers a desired root locale with the first entry at a distance of 80
  # whatever the threshold, so the distance is tested again here.
  defp closest_supported(requested, supported) do
    desired = requested.canonical_locale_id || requested

    case Localize.LanguageTag.best_match(desired, supported, @max_match_distance) do
      {:ok, entry, distance} when distance <= @max_match_distance ->
        {:ok, entry}

      {:ok, _entry, _distance} ->
        {:error,
         Localize.LocaleMatchError.exception(
           desired: requested.requested_locale_id,
           threshold: @max_match_distance
         )}

      {:error, _no_match} = error ->
        error
    end
  end

  # An entry that is already a validated tag is returned as it stands.
  defp served_locale(%Localize.LanguageTag{cldr_locale_id: locale_id} = locale)
       when not is_nil(locale_id) do
    {:ok, locale}
  end

  defp served_locale(entry) do
    Localize.validate_locale(entry)
  end

  # `Enum.find_value/3` takes any value but `nil` or `false` as found, so a
  # tag that matches no supported locale answers `nil`.
  defp matched({:ok, _locale} = match), do: match
  defp matched({:error, _no_match}), do: nil

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
