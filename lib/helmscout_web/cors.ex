defmodule HelmscoutWeb.CORS do
  @moduledoc """
  Permissive CORS for the public read-only API.

  The frontend is served from a different origin (e.g. Cloudflare Pages) than the
  API, so the browser needs these headers. The API is public and read-only, so by
  default we echo the requesting origin. Set `FRONTEND_ORIGINS` (comma-separated)
  to lock it down.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    origin = conn |> get_req_header("origin") |> List.first()

    conn =
      if origin && allowed?(origin) do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("vary", "origin")
        |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
        |> put_resp_header(
          "access-control-allow-headers",
          "content-type, authorization, mcp-protocol-version"
        )
        |> put_resp_header("access-control-max-age", "86400")
      else
        conn
      end

    if conn.method == "OPTIONS", do: send_resp(conn, 204, ""), else: conn
  end

  defp allowed?(origin) do
    case configured_origins() do
      :all -> true
      origins -> origin in origins
    end
  end

  defp configured_origins do
    case System.get_env("FRONTEND_ORIGINS") do
      nil -> :all
      "" -> :all
      "*" -> :all
      value -> value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end
  end
end
