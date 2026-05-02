defmodule PasseurFiles.Tools.SearchFiles do
  @moduledoc "Search file contents with ripgrep, returning a per-file match count and a snippet of the first match"

  use Anubis.Server.Component, type: :tool

  @file_cap 20
  @snippet_window 40

  schema do
    field :query, {:required, :string}, description: "Pattern to search for (regex)"
    field :path, :string, description: "Relative path to search within (default: root)"
    field :fixed_string, :boolean, description: "Treat query as a literal string, not a regex"
  end

  @impl true
  def execute(args, frame) do
    relative = args[:path] || "."

    with {:ok, search_root} <- PasseurFiles.safe_path(relative),
         {:ok, rg} <- find_rg() do
      results = run_rg(rg, args[:query], search_root, args[:fixed_string] == true)
      {:reply, reply(results), frame}
    else
      {:error, msg} ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.text("Error: #{msg}"),
         frame}
    end
  end

  defp find_rg do
    case System.find_executable("rg") do
      nil -> {:error, "ripgrep (rg) not found on PATH"}
      path -> {:ok, path}
    end
  end

  defp run_rg(rg, query, search_root, fixed_string?) do
    flags =
      ["-i", "--no-heading", "-n", "--column", "--color=never", "--"]
      |> then(fn f -> if fixed_string?, do: ["-F" | f], else: f end)

    args = flags ++ [query, search_root]

    port =
      Port.open({:spawn_executable, rg}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:args, args}
      ])

    collect(port, "", %{}, [])
  end

  # files: %{path => {count, first_match}}, order: [path] in encounter order
  defp collect(port, buffer, files, order) do
    receive do
      {^port, {:data, chunk}} ->
        {lines, rest} = split_lines(buffer <> chunk)
        {files, order, stop?} = ingest(lines, files, order)

        if stop? do
          Port.close(port)
          drain(port)
          finalize(files, order)
        else
          collect(port, rest, files, order)
        end

      {^port, {:exit_status, _}} ->
        {lines, _} = split_lines(buffer <> "\n")
        {files, order, _} = ingest(lines, files, order)
        finalize(files, order)
    end
  end

  defp drain(port) do
    receive do
      {^port, _} -> drain(port)
    after
      0 -> :ok
    end
  end

  defp split_lines(buffer) do
    parts = String.split(buffer, "\n")
    {Enum.drop(parts, -1), List.last(parts) || ""}
  end

  defp ingest([], files, order), do: {files, order, false}

  defp ingest([line | rest], files, order) do
    case parse_line(line) do
      nil ->
        ingest(rest, files, order)

      {path, lineno, col, text} ->
        case Map.fetch(files, path) do
          {:ok, {count, first}} ->
            ingest(rest, Map.put(files, path, {count + 1, first}), order)

          :error ->
            new_files = Map.put(files, path, {1, {lineno, col, text}})
            new_order = [path | order]

            if length(new_order) > @file_cap do
              {new_files, new_order, true}
            else
              ingest(rest, new_files, new_order)
            end
        end
    end
  end

  # rg with --no-heading -n --column emits: path:line:col:text
  defp parse_line(""), do: nil

  defp parse_line(line) do
    with [path, rest1] <- split_once(line, ":"),
         [lineno_s, rest2] <- split_once(rest1, ":"),
         [col_s, text] <- split_once(rest2, ":"),
         {lineno, ""} <- Integer.parse(lineno_s),
         {col, ""} <- Integer.parse(col_s) do
      {path, lineno, col, text}
    else
      _ -> nil
    end
  end

  defp split_once(s, sep) do
    case :binary.split(s, sep) do
      [a, b] -> [a, b]
      _ -> nil
    end
  end

  defp finalize(files, order) do
    ordered = Enum.reverse(order)
    truncated? = length(ordered) > @file_cap
    shown = Enum.take(ordered, @file_cap)

    {Enum.map(shown, fn path -> {path, Map.fetch!(files, path)} end), truncated?}
  end

  defp reply({[], _}) do
    Anubis.Server.Response.tool()
    |> Anubis.Server.Response.text("No matches.")
  end

  defp reply({entries, truncated?}) do
    root = PasseurFiles.root()

    lines =
      Enum.map(entries, fn {path, {count, {_lineno, col, text}}} ->
        rel = Path.relative_to(path, root)
        snippet = snippet(text, col)
        "- #{rel}: #{count} #{plural(count)}: #{snippet}"
      end)

    body =
      if truncated?,
        do: Enum.join(lines, "\n") <> "\nLimited to #{@file_cap} matches, additional files match.",
        else: Enum.join(lines, "\n")

    Anubis.Server.Response.tool()
    |> Anubis.Server.Response.text(body)
  end

  defp plural(1), do: "match"
  defp plural(_), do: "matches"

  defp snippet(text, col) do
    # col is 1-based byte offset of the match start
    start = max(col - 1 - @snippet_window, 0)
    pre_truncated? = start > 0
    len_after = @snippet_window * 2
    sliced = binary_part_safe(text, start, len_after)
    post_truncated? = byte_size(text) > start + byte_size(sliced)

    sliced
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> then(fn s -> if pre_truncated?, do: "…" <> s, else: s end)
    |> then(fn s -> if post_truncated?, do: s <> "…", else: s end)
  end

  defp binary_part_safe(bin, start, len) do
    available = max(byte_size(bin) - start, 0)
    take = min(len, available)
    if take > 0, do: binary_part(bin, start, take), else: ""
  end
end
