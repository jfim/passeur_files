defmodule PasseurFiles.Tools.DeleteFile do
  @moduledoc "Delete a file"

  use Anubis.Server.Component, type: :tool

  schema do
    field :path, {:required, :string}, description: "Relative path to the file to delete"
  end

  @impl true
  def execute(%{path: path}, frame) do
    case PasseurFiles.safe_path(path) do
      {:ok, full_path} ->
        case File.rm(full_path) do
          :ok ->
            {:reply,
             Anubis.Server.Response.tool()
             |> Anubis.Server.Response.text("Deleted #{path}"),
             frame}

          {:error, reason} ->
            {:reply,
             Anubis.Server.Response.tool()
             |> Anubis.Server.Response.text("Error deleting file: #{reason}"),
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
