#!/usr/bin/env elixir

ExUnit.start()

Code.require_file("./wiki.exs")

defmodule Wiki.HelpersTest do
  use ExUnit.Case

  @structure [
    "2023/January.md",
    "2023/February.md",
    "2023/March/5.md",
    "2022/December/31/Evening.md",
    "2021.md"
  ]

  test "subfolders/1" do
    assert Wiki.Helpers.subfolders(@structure) == ["2023", "2022"]
    assert Wiki.Helpers.subfolders(@structure, "2023") == ["2023/March"]
    assert Wiki.Helpers.subfolders(@structure, "2022") == ["2022/December"]
    assert Wiki.Helpers.subfolders(@structure, "2022/December") == ["2022/December/31"]
  end
end
