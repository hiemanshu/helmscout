defmodule Mix.Tasks.Helmscout.Prerender do
  @shortdoc "Prerender the home page into the built index.html"
  @moduledoc """
  Injects server-rendered HTML for the home page into `web/dist/index.html`.

  Run this **after** `npm run build` (it edits the build output):

      cd web && npm run build
      mix helmscout.prerender --dist web/dist
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [dist: :string])
    dist = opts[:dist] || "web/dist"

    :ok = Helmscout.Prerender.home(dist)
    Mix.shell().info("prerendered home page into #{dist}/index.html")
  end
end
