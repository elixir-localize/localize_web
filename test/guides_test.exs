defmodule Localize.GuidesTest do
  use ExUnit.Case, async: true

  # The `iex>` examples in the guides run as doctests, so a guide cannot
  # drift from the library it describes.
  doctest_file("guides/runtime-locale-routing.md")
end
