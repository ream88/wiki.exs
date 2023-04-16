#!/usr/bin/env elixir

Mix.install([:nimble_publisher])

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
      [filename: filename, private: private] = Keyword.take(keywords, [:filename, :private])

      filename =
        filename
        |> Path.relative_to(Wiki.Config.input_directory())
        |> Path.rootname()

      filename =
        Path.join([
          if(private, do: "private", else: "public"),
          filename <> ".html"
        ])

      keywords
      |> Keyword.put(:filename, filename)
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
    |> Enum.reduce([], fn
      dir, [] -> [dir]
      dir, [head | _] = acc -> [Path.join(head, dir) | acc]
    end)
    |> Enum.reverse()
  end
end

index_template = Path.join([File.cwd!(), "templates", "index.html.eex"])
page_template = Path.join([File.cwd!(), "templates", "page.html.eex"])

Wiki.pages()
|> Enum.map(& &1.category)
|> Enum.flat_map(&Wiki.Helpers.categories(&1))
|> Enum.uniq()
|> Enum.sort()
|> Enum.each(fn category ->
  pages = Enum.filter(Wiki.pages(), &(&1.category == category))

  {:ok, regex} = Regex.compile("^#{category}/\\w+$")

  sub_categories =
    Wiki.pages()
    |> Enum.map(& &1.category)
    |> Enum.flat_map(&Wiki.Helpers.categories(&1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.drop_while(&(&1 != category))
    |> Enum.drop(1)
    |> Enum.filter(&String.match?(&1, regex))

  path =
    [Wiki.Config.output_directory(), category, "index.html"]
    |> Path.join()
    |> Path.expand()

  index_template
  |> EEx.eval_file(assigns: [pages: pages, category: category, sub_categories: sub_categories])
  |> Wiki.Helpers.write_file(path)
end)

Enum.each(Wiki.pages(), fn page ->
  path = Path.join(Wiki.Config.output_directory(), page.filename)

  page_template
  |> EEx.eval_file(assigns: [page: page])
  |> Wiki.Helpers.write_file(path)
end)
