defmodule Mix.Tasks.Helmscout.Index do
  @shortdoc "Fetch + index sources into the search database"
  @moduledoc """
  Fetches and indexes sources that have already been discovered.

      mix helmscout.index
      mix helmscout.index --limit 25
      mix helmscout.index --only-stale 7
      mix helmscout.index --concurrency 8
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    Helmscout.Tasks.ensure_database!()

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [limit: :integer, only_stale: :integer, concurrency: :integer, force: :boolean]
      )

    stats =
      Helmscout.Pipeline.index_all(
        limit: opts[:limit],
        only_stale_days: opts[:only_stale],
        concurrency: opts[:concurrency] || System.schedulers_online(),
        force: opts[:force] || false
      )

    Mix.shell().info("""

    indexed #{stats.total} sources:
      ok:      #{stats.ok}
      empty:   #{stats.empty}
      skipped: #{stats.skipped}
      error:   #{stats.error}
      releases found: #{stats.releases}
    """)
  end
end
