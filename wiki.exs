#!/usr/bin/env elixir

Mix.install([:nimble_publisher])

{opts, _, _} =
  OptionParser.parse(System.argv(),
    strict: [private: :boolean],
    aliases: [p: :private]
  )

if Keyword.get(opts, :private, false) do
  IO.puts("WARNING: Private pages are generated!")
end

defmodule Wiki.Config do
  @input_directory "input"
  def input_directory(), do: Path.join(File.cwd!(), @input_directory)

  @output_directory "output"
  def output_directory(), do: Path.join(File.cwd!(), @output_directory)
end

defmodule Wiki.Page do
  defstruct private: true,
            title: nil,
            content: nil,
            tags: [],
            filename: nil,
            category: nil

  def new(attrs \\ []) do
    attrs
    |> Keyword.update(:private, true, &(!!&1))
    |> then(fn keywords ->
      {filename, keywords} = Keyword.pop!(keywords, :filename)

      filename =
        filename
        |> Path.relative_to(Wiki.Config.input_directory())
        |> Path.rootname(".md")

      keywords
      |> Keyword.put(:filename, filename <> ".html")
      |> Keyword.put(:category, Path.dirname(filename))
      |> Keyword.put_new_lazy(:title, fn -> filename end)
    end)
    |> then(&struct(__MODULE__, &1))
  end

  def build(filename, attrs, body) do
    attrs
    |> Enum.into([])
    |> Keyword.merge(filename: filename, content: body)
    |> new()
  end

  def last_modified_date() do
    {_data, 0} = System.cmd("git", [])
  end
end

defmodule Wiki do
  use NimblePublisher,
    build: Wiki.Page,
    from: "#{Wiki.Config.input_directory()}/**/*.md",
    as: :pages

  def pages(), do: @pages
end

defmodule Wiki.Helpers do
  def write_file(content, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  def categories(path) when is_binary(path) do
    path
    |> Path.split()
    |> Enum.reduce([""], fn
      dir, [] -> [dir]
      dir, [head | _] = acc -> [Path.join(head, dir) | acc]
    end)
    |> Enum.reverse()
  end
end

index_template = Path.join([File.cwd!(), "templates", "index.html.eex"])
page_template = Path.join([File.cwd!(), "templates", "page.html.eex"])
error_403_template = Path.join([File.cwd!(), "templates", "403.html.eex"])

Wiki.pages()
|> Enum.map(& &1.category)
|> Enum.flat_map(&Wiki.Helpers.categories(&1))
|> Enum.uniq()
|> Enum.sort()
|> Enum.each(fn category ->
  pages = Enum.filter(Wiki.pages(), &(&1.category == category))

  sub_categories =
    Wiki.pages()
    |> Enum.map(& &1.category)
    |> Enum.flat_map(&Wiki.Helpers.categories(&1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.filter(&String.starts_with?(&1, category))
    |> Enum.reject(&(&1 == category))
    |> Enum.reject(&String.contains?(String.replace_leading(&1, category <> "/", ""), "/"))

  path =
    [Wiki.Config.output_directory(), category, "index.html"]
    |> Path.join()
    |> Path.expand()

  index_template
  |> EEx.eval_file(assigns: [pages: pages, category: category, sub_categories: sub_categories])
  |> Wiki.Helpers.write_file(path)
end)

Enum.each(Wiki.pages(), fn page ->
  template =
    if !page.private || Keyword.get(opts, :private, false) do
      page_template
    else
      error_403_template
    end

  path = Path.join(Wiki.Config.output_directory(), page.filename)

  template
  |> EEx.eval_file(assigns: [page: page])
  |> Wiki.Helpers.write_file(path)
end)
