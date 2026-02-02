defmodule Lyt.API.Error do
  @moduledoc """
  Standardized error responses for the Lyt API.
  """

  import Plug.Conn

  @doc """
  Send an error response for the given error type.
  """
  def respond(conn, {:validation, errors}) do
    details = format_validation_errors(errors)

    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(400, Jason.encode!(%{ok: false, error: "validation_error", details: details}))
  end

  def respond(conn, :payload_too_large) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(413, Jason.encode!(%{ok: false, error: "payload_too_large"}))
  end

  def respond(conn, :not_found) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(404, Jason.encode!(%{ok: false, error: "not_found"}))
  end

  def respond(conn, :internal_error) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(500, Jason.encode!(%{ok: false, error: "internal_error"}))
  end

  defp format_validation_errors(errors) when is_list(errors) do
    Enum.reduce(errors, %{}, fn {field, message}, acc ->
      field_str = to_string(field)
      Map.update(acc, field_str, [message], &[message | &1])
    end)
  end
end
