defmodule MyApp.JSON do
  @moduledoc false

  # The `:json_library` for Phoenix in tests, built on Erlang's `:json`
  # (native from OTP 27, `json_polyfill` on OTP 26) since the library's
  # Elixir floor predates Elixir's `JSON`. Phoenix calls only these three
  # functions. `:json` writes `nil` as "nil" and reads null as `:null`, so
  # both are mapped explicitly.

  def encode!(term), do: term |> encode_to_iodata!() |> IO.iodata_to_binary()

  def encode_to_iodata!(term), do: :json.encode(term, &encode_value/2)

  def decode!(json) do
    json = IO.iodata_to_binary(json)

    case :json.decode(json, :ok, %{null: nil}) do
      {value, :ok, rest} ->
        if String.trim(rest) == "" do
          value
        else
          raise ArgumentError, "unexpected trailing data in JSON: #{inspect(rest)}"
        end
    end
  end

  defp encode_value(nil, _encoder), do: "null"
  defp encode_value(value, encoder), do: :json.encode_value(value, encoder)
end
