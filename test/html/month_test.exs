defmodule Localize.HTML.Month.Test do
  use ExUnit.Case

  @moduledoc """
  Covers month option labels when a non-default calendar module is requested.

  These tests keep the month list explicit; they do not cover deriving month counts
  from calendar years.
  """

  defmodule HebrewCalendar do
    @moduledoc false

    def cldr_calendar_type, do: :hebrew
  end

  defmodule PersianCalendar do
    @moduledoc false

    def cldr_calendar_type, do: :persian
  end

  defmodule PlainCalendar do
    @moduledoc false
  end

  @hebrew_calendar __MODULE__.HebrewCalendar
  @persian_calendar __MODULE__.PersianCalendar
  @plain_calendar __MODULE__.PlainCalendar

  describe "month_options/1" do
    test "uses Gregorian labels by default" do
      assert [{"January", 1}, {"December", 12}] =
               Localize.HTML.Month.month_options(
                 months: [1, 12],
                 locale: :en
               )
    end

    test "uses the requested calendar module for option labels" do
      assert [{"Tishri", 1}] =
               Localize.HTML.Month.month_options(
                 calendar: @hebrew_calendar,
                 months: [1],
                 locale: :en
               )

      assert [{"Farvardin", 1}] =
               Localize.HTML.Month.month_options(
                 calendar: @persian_calendar,
                 months: [1],
                 locale: :en
               )
    end

    test "falls back to Gregorian labels when the calendar module does not identify a CLDR calendar" do
      assert [{"January", 1}] =
               Localize.HTML.Month.month_options(
                 calendar: @plain_calendar,
                 months: [1],
                 locale: :en
               )
    end

    test "keeps the default month list explicit" do
      options =
        Localize.HTML.Month.month_options(
          calendar: @hebrew_calendar,
          locale: :en
        )

      assert length(options) == 12
      assert Enum.map(options, fn {_label, month} -> month end) == Enum.to_list(1..12)
    end
  end
end
