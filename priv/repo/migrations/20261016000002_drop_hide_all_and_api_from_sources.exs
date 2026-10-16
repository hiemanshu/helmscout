defmodule Helmscout.Repo.Migrations.DropHideAllAndApiFromSources do
  use Ecto.Migration

  # Opt-out is now just `helmscout-hide-mcp` (see Helmscout.Visibility). To leave
  # helmscout entirely, make the repository private — only public repos are
  # indexed.
  def change do
    alter table(:sources) do
      remove :hide_all, :boolean, null: false, default: false
      remove :hide_api, :boolean, null: false, default: false
    end
  end
end
