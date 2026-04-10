defmodule PasseurFiles.Tools.WriteFile do
  @moduledoc "Create or overwrite a file with the given content"

  use Anubis.Server.Component, type: :tool

  schema do
    field :path, {:required, :string}, description: "Relative path to the file"
    field :content, {:required, :string}, description: "Content to write"
  end

  @impl true
  def execute(%{path: path, content: content}, frame) do
    case PasseurFiles.safe_path(path) do
      {:ok, full_path} ->
        full_path |> Path.dirname() |> File.mkdir_p!()

        case File.write(full_path, content) do
          :ok ->
            {:reply,
             Anubis.Server.Response.tool()
             |> Anubis.Server.Response.text("Written to #{path}"),
             frame}

          {:error, reason} ->
            {:reply,
             Anubis.Server.Response.tool()
             |> Anubis.Server.Response.text("Error writing file: #{reason}"),
             frame}
        end

      {:error, msg} ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.text("Error: #{msg}"),
         frame}
    end
  end
end
