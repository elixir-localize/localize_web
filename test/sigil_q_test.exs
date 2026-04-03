defmodule Sigil_q.Test do
  use ExUnit.Case

  use Localize.VerifiedRoutes,
    router: MyApp.Router,
    endpoint: MyApp.Endpoint,
    gettext: MyApp.Gettext

  test "sigil_q for default locale" do
    Localize.put_locale(:en)
    assert ~q[/users] == "/users"
  end

  test "sigil_q for :fr locale" do
    Localize.put_locale(:fr)
    assert ~q[/users] == "/users_fr"
  end

  test "sigil_q with locale interpolation" do
    Localize.put_locale(:de)
    assert ~q[/users/:locale] == "/users_de/de"
  end

  test "sigil_q with language interpolation" do
    Localize.put_locale(:de)
    assert ~q[/users/:language] == "/users_de/de"
  end

  test "sigil_q with territory interpolation" do
    Localize.put_locale(:de)
    assert ~q[/users/:territory] == "/users_de/de"
  end

  test "sigil_q with interpolations" do
    Localize.put_locale(:fr)
    assert ~q[/users/:user] == "/users_fr/:user"
  end

  test "sigil_q with multiple path segments and interpolation" do
    Localize.put_locale(:fr)
    user_id = 1
    face_id = 2

    assert ~q[/users/#{user_id}/faces/#{face_id}/:locale/visages] ==
             "/users_fr/1/faces_fr/2/fr/visages"
  end

  test "sigil_q with query params" do
    Localize.put_locale(:en)
    assert ~q"/users/17?admin=true&active=false" == "/users/17?admin=true&active=false"
    assert ~q"/users/17?#{[admin: true]}" == "/users/17?admin=true"
  end

  test "sigil_q with url/1" do
    Localize.put_locale(:en)
    assert url(~q[/users/:territory]) == "http://localhost/users/us"
    assert url(MyApp.Endpoint, ~q[/users/:territory]) == "http://localhost/users/us"
    assert url(MyApp.Endpoint, MyApp.Router, ~q[/users/:territory]) == "http://localhost/users/us"

    Localize.put_locale(:de)
    assert url(~q[/users/:territory]) == "http://localhost/users_de/de"
    assert url(MyApp.Endpoint, ~q[/users/:territory]) == "http://localhost/users_de/de"

    assert url(MyApp.Endpoint, MyApp.Router, ~q[/users/:territory]) ==
             "http://localhost/users_de/de"
  end

  test "sigil_p with url/1" do
    assert url(~p[/users/us]) == "http://localhost/users/us"
    assert url(MyApp.Endpoint, ~p[/users/us]) == "http://localhost/users/us"
    assert url(MyApp.Endpoint, MyApp.Router, ~p[/users/us]) == "http://localhost/users/us"
  end
end
