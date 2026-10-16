defmodule Helmscout.Repo.Migrations.AddHideFlagsToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      # Opt-out. Set from a GitHub topic or a marker file in the repo:
      #   helmscout-hide / .helmscout-hide          - not indexed at all
      #   helmscout-hide-api / .helmscout-hide-api  - excluded from /api (and the site)
      #   helmscout-hide-mcp / .helmscout-hide-mcp  - excluded from the MCP server
      add :hide_all, :boolean, null: false, default: false
      add :hide_api, :boolean, null: false, default: false
      add :hide_mcp, :boolean, null: false, default: false
    end
  end
end
