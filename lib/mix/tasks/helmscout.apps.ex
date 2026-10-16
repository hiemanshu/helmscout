defmodule Mix.Tasks.Helmscout.Apps do
  @shortdoc "Backfill app/image identity for existing releases (no cloning)"
  @moduledoc """
  Recomputes the inferred app name and container images for every stored release
  from its already-indexed values. Cheap; safe to run any time.

      mix helmscout.apps
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(_args) do
    Helmscout.Tasks.ensure_database!()
    count = Helmscout.Apps.backfill()
    Mix.shell().info("backfilled app/images for #{count} releases")
  end
end
