defmodule HelmscoutWeb.StaticFrontend do
  @moduledoc """
  Serves the SPA's static files (hashed assets + root files). `index.html` is
  intentionally *not* served here — the router handles `/` so it can inject the
  server-rendered home page.
  """

  @behaviour Plug

  @impl true
  def init(_opts) do
    # Serve everything from the build except index.html, which the router handles
    # (so it can inject the server-rendered home page).
    Plug.Static.init(
      at: "/",
      from: HelmscoutWeb.Frontend.dir(),
      except: ["index.html"],
      gzip: false
    )
  end

  @impl true
  def call(conn, opts), do: Plug.Static.call(conn, opts)
end
