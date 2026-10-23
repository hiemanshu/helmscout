defmodule HelmscoutWeb.StaticFrontend do
  @moduledoc """
  Serves the SPA's static files (hashed assets + root files). `index.html` is
  intentionally *not* served here — the router handles `/` so it can inject the
  server-rendered home page.

  The options are resolved on the first request instead of in `init/1`. Phoenix
  initialises plugs at compile time by default, which is too early to know
  `FRONTEND_DIR` (and the release's runtime path); with compile-time options
  `Plug.Static` would point at the build-time `web/dist` and every asset would
  fall through to the SPA shell as `text/html`.
  """

  @behaviour Plug

  @impl true
  def init(_opts), do: nil

  @impl true
  def call(conn, _opts) do
    Plug.Static.call(conn, static_opts())
  end

  defp static_opts do
    case :persistent_term.get({__MODULE__, :opts}, nil) do
      nil ->
        opts =
          Plug.Static.init(
            at: "/",
            from: HelmscoutWeb.Frontend.dir(),
            except: ["index.html"],
            gzip: false
          )

        :persistent_term.put({__MODULE__, :opts}, opts)
        opts

      opts ->
        opts
    end
  end
end
