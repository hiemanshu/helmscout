defmodule HelmscoutWeb.Frontend do
  @moduledoc """
  Locates and serves the built Vue app.

  In development that's `web/dist`; in a release it's
  `priv/static/frontend` (copied in at build time). Override with
  `FRONTEND_DIR`.
  """

  @doc "Directory containing the built SPA (index.html + assets/)."
  def dir do
    Application.get_env(:helmscout, :frontend_dir) || default_dir()
  end

  @doc "The SPA shell (`index.html`), or a helpful message if it isn't built."
  def index_html do
    index = Path.join(dir(), "index.html")

    case File.read(index) do
      {:ok, html} ->
        html

      {:error, _} ->
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>helmscout</title></head>
        <body style="font-family: system-ui; max-width: 40rem; margin: 4rem auto">
        <h1>helmscout</h1>
        <p>the frontend isn't built yet — run <code>cd web &amp;&amp; npm run build</code>
        (expected at <code>#{index}</code>).</p>
        <p>the API is available at <a href="/api/home">/api/home</a> and MCP at <code>/mcp</code>.</p>
        </body></html>
        """
    end
  end

  defp default_dir, do: Path.join(File.cwd!(), "web/dist")
end
