defmodule HelmscoutWeb.Router do
  @moduledoc false

  use Phoenix.Router

  import Plug.Conn

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html", "json"]
  end

  # MCP (Model Context Protocol) endpoint - Streamable HTTP transport (POST).
  # The docs page lives at `/mcp`; the protocol lives here under /api.
  forward "/api/mcp", HelmscoutWeb.MCP

  scope "/api", HelmscoutWeb do
    pipe_through :api

    get "/home", SearchController, :home
    get "/stats", SearchController, :stats
    get "/popular", SearchController, :popular
    get "/charts", SearchController, :charts
    get "/apps", SearchController, :apps
    get "/apps/:app/recommendations", SearchController, :recommendations
    get "/apps/:app", SearchController, :app
    get "/releases", SearchController, :releases
    get "/releases/:id/values", SearchController, :values
    get "/sources", SearchController, :sources
    get "/random", SearchController, :random

    get("/*path", SearchController, :not_found)
  end

  scope "/", HelmscoutWeb do
    pipe_through :browser

    get "/health", HealthController, :show
    get "/sitemap.xml", SitemapController, :index

    # SPA: everything else renders the app shell (server-rendered home at "/").
    # `/mcp` is the MCP docs page; the protocol is at /api/mcp.
    get "/config.json", SpaController, :config
    get "/", SpaController, :index
    get "/*path", SpaController, :index
  end
end
