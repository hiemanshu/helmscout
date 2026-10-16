defmodule Helmscout.Repo.Migrations.CreateSources do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :key, :string, null: false
      add :name, :string, null: false
      add :forge, :string, null: false, default: "github"
      add :url, :string, null: false
      add :branch, :string, default: "main"
      add :stars, :integer, null: false, default: 0
      add :pushed_at, :utc_datetime
      add :discoverers, {:array, :string}, null: false, default: []
      add :topics, {:array, :string}, null: false, default: []
      add :last_indexed_at, :utc_datetime
      add :last_commit_sha, :string
      add :release_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sources, [:key])
    create index(:sources, [:stars])
    create index(:sources, [:last_indexed_at])
  end
end
