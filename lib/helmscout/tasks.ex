defmodule Helmscout.Tasks do
  @moduledoc """
  Shared preflight for the pipeline mix tasks.

  The pipeline needs the database to exist and be migrated; running
  `ecto.create` + `ecto.migrate` here means `mix helmscout.update` works on a
  fresh machine (and in CI) instead of failing with `database ... does not
  exist`.
  """

  @doc "Create + migrate the database, ignoring 'already exists' style errors."
  def ensure_database! do
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])
  rescue
    _ -> :ok
  end
end
