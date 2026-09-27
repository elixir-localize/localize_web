defmodule Localize.HTML.Options do
  @moduledoc false

  # Option validation shared by the HTML select helpers. The helpers run
  # on the render path, so every function here returns `{:ok, value}` or
  # `{:error, exception}` and never raises, whatever it is given.

  alias Localize.InvalidValueError

  @doc false
  # The caller's options merged over the helper's defaults, as a map.
  def merge(options, defaults) when is_list(options) do
    if Keyword.keyword?(options) do
      {:ok, Map.merge(defaults, Map.new(options))}
    else
      invalid(options, :keyword_list)
    end
  end

  def merge(options, _defaults), do: invalid(options, :keyword_list)

  @doc false
  # Resolves the `:locale` option to a language tag.
  def locale(%{locale: locale} = options) do
    with {:ok, locale} <- Localize.validate_locale(locale) do
      {:ok, Map.put(options, :locale, locale)}
    end
  end

  @doc false
  # Checks that the option is a function of arity 1.
  def function(options, key) do
    case Map.fetch!(options, key) do
      function when is_function(function, 1) -> {:ok, options}
      other -> invalid(other, key, nil, "a function of arity 1")
    end
  end

  @doc false
  # Checks that the option is one of `allowed`.
  def one_of(options, key, allowed) do
    value = Map.fetch!(options, key)

    if value in allowed do
      {:ok, options}
    else
      invalid(value, key, allowed)
    end
  end

  @doc false
  # Validates each element of a list option with `validator`, keeping
  # the validated values in order.
  def list(options, key, validator) do
    case Map.fetch!(options, key) do
      values when is_list(values) ->
        with {:ok, values} <- validate_each(values, validator) do
          {:ok, Map.put(options, key, values)}
        end

      other ->
        invalid(other, key, nil, "a list")
    end
  end

  defp validate_each(values, validator) do
    values
    |> Enum.reduce_while([], fn value, acc ->
      case validator.(value) do
        {:ok, value} -> {:cont, [value | acc]}
        {:error, exception} -> {:halt, {:error, exception}}
      end
    end)
    |> case do
      {:error, exception} -> {:error, exception}
      values -> {:ok, Enum.reverse(values)}
    end
  end

  @doc false
  # Validates an optional value with `validator`; `nil` is kept.
  def optional(options, key, validator) do
    case Map.fetch!(options, key) do
      nil ->
        {:ok, options}

      value ->
        with {:ok, value} <- validator.(value) do
          {:ok, Map.put(options, key, value)}
        end
    end
  end

  @doc false
  # Passes an atom or string code to a Localize validator.
  #
  # `Localize.Currency.validate_currency/1` and `Localize.validate_territory/1`
  # in Localize 1.3.0 raise `FunctionClauseError` for other terms. This is
  # fixed on Localize main; once that is on hex and required here, this
  # check can go. See TODO.md.
  def code(code, _expected, validator) when is_atom(code) or is_binary(code) do
    validator.(code)
  end

  def code(code, expected, _validator), do: invalid(code, expected)

  @doc false
  def invalid(value, expected, allowed \\ nil, label \\ nil) do
    {:error,
     InvalidValueError.exception(
       value: value,
       expected: label || expected,
       allowed_values: allowed,
       context: if(label, do: expected)
     )}
  end
end
