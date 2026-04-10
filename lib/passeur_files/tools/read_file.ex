defmodule PasseurFiles.Tools.ReadFile do
  @moduledoc "Read the contents of a file"

  use Anubis.Server.Component, type: :tool

  schema do
    field :path, {:required, :string}, description: "Relative path to the file"
  end

  @impl true
  def execute(%{path: path}, frame) do
    case PasseurFiles.safe_path(path) do
      {:ok, full_path} ->
        case File.read(full_path) do
          {:ok, content} ->
            {:reply,
             Anubis.Server.Response.tool()
             |> Anubis.Server.Response.text(content),
             frame}

          {:error, reason} ->
            {:reply,
             Anubis.Server.Response.tool()
             |> Anubis.Server.Response.text("Error reading file: #{reason}"),
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
