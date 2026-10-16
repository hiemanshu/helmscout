defmodule HelmscoutWeb.SitemapController do
  @moduledoc false

  use HelmscoutWeb, :controller

  alias Helmscout.Search

  @core ["", "sources", "stats", "mcp", "about"]

  def index(conn, _params) do
    base = Application.get_env(:helmscout, :base_url, "https://helmscout.dev")

    app_urls =
      Search.top_apps(500) |> Enum.map(&"app/#{URI.encode(to_string(&1.app))}")

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(@core ++ app_urls, "\n", &"  <url><loc>#{base}/#{&1}</loc></url>")}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end
end
