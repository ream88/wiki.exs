#!/usr/bin/env elixir

require Logger

Application.put_env(:tailwind, :version, "3.2.4")
Mix.install([:nimble_publisher, :tailwind])

defmodule Wiki.Config do
  @input_directory "input"
  def input_directory(), do: Path.join(File.cwd!(), @input_directory)

  @output_directory "output"
  def output_directory(), do: Path.join(File.cwd!(), @output_directory)
end

defmodule Wiki.Page do
  defstruct filename: "",
            private: true,
            title: nil,
            tags: [],
            content: nil

  def build(filename, attrs, body) do
    attrs
    |> Enum.into([])
    |> Keyword.merge(filename: filename, content: body)
    |> new()
  end

  def new(attrs \\ []) do
    attrs
    |> Keyword.update(:private, true, &(!!&1))
    |> then(fn opts ->
      opts
      |> Keyword.update!(:filename, &Path.relative_to(&1, Wiki.Config.input_directory()))
      |> Keyword.put_new_lazy(
        :title,
        fn ->
          attrs
          |> Keyword.fetch!(:filename)
          |> Path.basename(".md")
        end
      )
    end)
    |> then(&struct(__MODULE__, &1))
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

  def build(opts \\ []) do
    File.rm_rf(Wiki.Config.output_directory())
    generate_index_pages(opts)
    generate_pages(opts)
    generate_css(opts)
  end

  defp generate_index_pages(opts) do
    index_template = Path.join([File.cwd!(), "templates", "index.html.eex"])

    pages()
    |> Enum.map(& &1.filename)
    |> Enum.map(&Path.dirname(&1))
    |> Enum.flat_map(&Wiki.Helpers.nested_paths/1)
    |> Enum.uniq()
    |> Enum.each(fn path ->
      full_path = Path.expand(Path.join([Wiki.Config.output_directory(), path, "index.html"]))

      folders =
        pages()
        |> Enum.map(& &1.filename)
        |> Wiki.Helpers.subfolders(path)

      pages =
        pages()
        |> Enum.filter(&(Path.dirname(&1.filename) == path))
        |> Enum.map(fn page ->
          %{page | filename: String.replace_suffix(page.filename, ".md", ".html")}
        end)

      assigns = [
        root_path: String.replace(path, ~r(\w+), ".."),
        current_path: if(path == ".", do: "", else: path),
        title: "Index of #{inspect(path)}",
        folders: folders,
        pages: pages
      ]

      index_template
      |> EEx.eval_file(assigns: assigns)
      |> Wiki.Helpers.write_file(full_path)
    end)
  end

  defp generate_pages(opts) do
    page_template = Path.join([File.cwd!(), "templates", "page.html.eex"])
    error_403_template = Path.join([File.cwd!(), "templates", "403.html.eex"])

    Enum.each(pages(), fn page ->
      full_path =
        Path.join(
          Wiki.Config.output_directory(),
          String.replace_suffix(page.filename, ".md", ".html")
        )

      assigns = [
        root_path: String.replace(Path.dirname(page.filename), ~r(\w+), ".."),
        current_path: Path.dirname(page.filename),
        page: page
      ]

      if !page.private || Keyword.get(opts, :private, false) do
        page_template
      else
        error_403_template
      end
      |> EEx.eval_file(assigns: assigns)
      |> Wiki.Helpers.write_file(full_path)
    end)
  end

  def generate_css(_opts) do
    Mix.Tasks.Tailwind.run([
      "default",
      "--config=tailwind.config.js",
      "--input=templates/style.css",
      "--output=output/style.css",
      "--minify"
    ])
  end
end

defmodule Wiki.Helpers do
  def write_file(content, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    Logger.debug("Writing #{path}")
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

  def subfolders(folders, parent \\ ".") do
    parent = if parent == ".", do: "", else: parent
    parent_length = length(Path.split(parent))

    folders
    |> Enum.map(&Path.dirname/1)
    |> Enum.reject(&(&1 == "."))
    |> Enum.filter(fn folder ->
      String.starts_with?(folder, parent) &&
        Enum.count(Path.split(folder)) > parent_length
    end)
    |> Enum.map(&Path.split/1)
    |> Enum.map(&Enum.take(&1, parent_length + 1))
    |> Enum.map(&Path.join/1)
    |> Enum.uniq()
  end

  def breadcrumbs(path) do
    case path do
      "." ->
        []

      path ->
        path
        |> Path.split()
        |> Enum.map_reduce([], fn folder, acc -> {Path.join(acc ++ [folder]), acc ++ [folder]} end)
        |> Tuple.to_list()
        |> Enum.zip()
    end
  end

  # Old helpers?
  def nested_paths(path) do
    path
    |> Path.split()
    |> Enum.reduce([], fn
      directory, [] -> [[directory]]
      directory, path -> [List.flatten([directory | hd(path)]) | path]
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.map(&Path.join/1)
    |> Enum.reverse()
  end

  def application_started?(name) do
    Application.started_applications()
    |> Enum.map(&elem(&1, 0))
    |> Enum.member?(name)
  end
end

unless Wiki.Helpers.application_started?(:ex_unit) do
  {opts, _, _} =
    OptionParser.parse(System.argv(),
      strict: [private: :boolean],
      aliases: [p: :private]
    )

  if Keyword.get(opts, :private, false) do
    IO.puts("#{IO.ANSI.red()}WARNING:#{IO.ANSI.reset()} Private pages are generated!")
  end

  Wiki.build(opts)
end
