defmodule Localize.Plug.LiveSessionLocaleTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Localize.Plug.PutLocale

  test "returns the resolved locale as a string under the session key" do
    conn =
      :get
      |> conn("/?locale=fr")
      |> PutLocale.call(PutLocale.init(from: [:query]))

    assert Localize.Plug.live_session_locale(conn) == %{"localize_locale" => "fr"}
  end

  test "is read back by put_locale_from_session/2" do
    conn =
      :get
      |> conn("/?locale=de")
      |> PutLocale.call(PutLocale.init(from: [:query]))

    session = Localize.Plug.live_session_locale(conn)

    assert {:ok, %Localize.LanguageTag{cldr_locale_id: :de}} =
             Localize.Plug.put_locale_from_session(session)
  end

  test "is an empty map when no locale was set, and for anything that is not a conn" do
    unresolved =
      :get
      |> conn("/")
      |> PutLocale.call(PutLocale.init(from: [:query], default: :none))

    for value <- [unresolved, conn(:get, "/"), nil, %{}, "conn"] do
      assert Localize.Plug.live_session_locale(value) == %{}
    end
  end
end
