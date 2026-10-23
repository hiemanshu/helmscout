defmodule HelmscoutWeb.SpaController do
  @moduledoc """
  Serves the SPA shell for every client-side route.

  `/` gets the **server-rendered** home page injected into the mount point, so it
  paints immediately and is crawlable; Vue replaces it on hydration.
  """

  use HelmscoutWeb, :controller

  def index(conn, _params) do
    html = HelmscoutWeb.Frontend.index_html()
    html = if conn.request_path == "/", do: inject_home(html), else: html

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  Runtime config for the SPA. A `config.json` file in the build (written at
  deploy time) is served directly by the static plug; this only answers the
  "no file present" case so the SPA gets JSON instead of the HTML shell.
  """
  def config(conn, _params) do
    json(conn, %{})
  end

  @doc "404 for missing static assets (the SPA shell must not answer these)."
  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "not found")
  end

  defp inject_home(html) do
    body = Helmscout.Prerender.render_home()

    String.replace(html, ~r{<div id="app">\s*</div>}, ~s(<div id="app">#{body}</div>),
      global: false
    )
  end
end
