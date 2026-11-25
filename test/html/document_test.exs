defmodule Localize.HTML.DocumentTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  alias Localize.HTML.Document

  doctest Localize.HTML.Document

  describe "attributes/1" do
    test "gives the canonical tag and the direction of the locale's script" do
      for {locale, lang, dir} <- [
            {"ar", "ar", "rtl"},
            {:fa, "fa", "rtl"},
            {"he", "he", "rtl"},
            {"ur", "ur", "rtl"},
            {"pa-Arab", "pa-Arab", "rtl"},
            {"pa", "pa", "ltr"},
            {"en", "en", "ltr"},
            {"zh-Hant", "zh-Hant", "ltr"},
            {"es_MX", "es-MX", "ltr"}
          ] do
        assert {locale, Document.attributes(locale)} == {locale, {:ok, [lang: lang, dir: dir]}}
      end
    end

    test "takes a language tag, and the current locale by default" do
      {:ok, tag} = Localize.validate_locale("ar")
      assert Document.attributes(tag) == {:ok, [lang: "ar", dir: "rtl"]}

      {:ok, _locale} = Localize.put_locale(:ar)
      assert Document.attributes() == {:ok, [lang: "ar", dir: "rtl"]}
    end

    test "returns an error, never raises, for a value that is not a locale" do
      for locale <- [nil, "", "not a locale!", 42, %{}, ["en"]] do
        assert {:error, %{__exception__: true}} = Document.attributes(locale), inspect(locale)
      end
    end
  end

  describe "html/1" do
    test "renders <html> with lang, dir and the other attributes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Document.html locale="ar" class="h-full"><body>نص</body></Document.html>
        """)

      assert html =~ ~s(<html lang="ar" dir="rtl" class="h-full">)
      assert html =~ "<body>نص</body></html>"
    end

    test "takes the current locale by default" do
      {:ok, _locale} = Localize.put_locale(:fr)
      assigns = %{}

      assert rendered_to_string(~H"<Document.html><body></body></Document.html>") =~
               ~s(<html lang="fr" dir="ltr">)
    end

    test "logs a locale that is not valid and renders <html> without lang and dir" do
      assigns = %{}

      log =
        capture_log(fn ->
          html =
            rendered_to_string(
              ~H|<Document.html locale="not a locale!"><body></body></Document.html>|
            )

          send(self(), {:html, html})
        end)

      assert_received {:html, html}
      assert html =~ "<html><body></body></html>"
      assert log =~ "Localize.HTML.Document.html/1"
    end
  end

  describe "live_locale/1" do
    test "renders a hidden element that sets lang and dir on <html> when it mounts" do
      assigns = %{}
      html = rendered_to_string(~H|<Document.live_locale locale="fa" />|)

      assert html =~ ~s(id="localize-document-fa")
      assert html =~ "hidden"
      assert html =~ "phx-mounted="
      assert html =~ "set_attr"
      assert html =~ "[&quot;lang&quot;,&quot;fa&quot;]"
      assert html =~ "[&quot;dir&quot;,&quot;rtl&quot;]"
    end

    test "names the locale in its id, so a page in another locale replaces it" do
      assigns = %{}

      assert rendered_to_string(~H|<Document.live_locale locale="en" />|) =~
               ~s(id="localize-document-en")

      assert rendered_to_string(~H|<Document.live_locale locale="ar" />|) =~
               ~s(id="localize-document-ar")
    end

    test "logs a locale that is not valid and renders nothing" do
      assigns = %{}

      log =
        capture_log(fn ->
          send(self(), {:html, rendered_to_string(~H|<Document.live_locale locale={42} />|)})
        end)

      assert_received {:html, ""}
      assert log =~ "Localize.HTML.Document.live_locale/1"
    end
  end
end
