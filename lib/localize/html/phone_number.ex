if Code.ensure_loaded?(Localize.PhoneNumber.Number) do
  defmodule Localize.HTML.PhoneNumber do
    @moduledoc """
    Phoenix.HTML integration for localized phone number display.

    Implements `Phoenix.HTML.Safe` for `Localize.PhoneNumber.Number` so a
    parsed phone number can be rendered directly in HEEx templates and used
    as a form input value without raising `Protocol.UndefinedError`.

    The rendered value is delegated to `Localize.Chars` — the locale-aware
    string protocol — so it matches what a user gets from the localized
    renderer, mirroring the `Phoenix.HTML.Safe` implementation for `Money`
    in `ex_money`. For a phone number `Localize.Chars` resolves to the
    international format (`+1 650-253-0000`).

    Compiled only when the optional `localize_phone_number` dependency is
    present in the consuming application.
    """
  end

  defimpl Phoenix.HTML.Safe, for: Localize.PhoneNumber.Number do
    def to_iodata(number) do
      string =
        case Localize.Chars.to_string(number) do
          {:ok, formatted} -> formatted
          {:error, _reason} -> number.raw_input
        end

      # Route through the BitString implementation so the result is escaped,
      # guarding the user-supplied raw_input fallback. Mirrors ex_money.
      Phoenix.HTML.Safe.to_iodata(string)
    end
  end
end
