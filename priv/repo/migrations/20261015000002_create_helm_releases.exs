defmodule Helmscout.Repo.Migrations.CreateHelmReleases do
  use Ecto.Migration

  def change do
    create table(:helm_releases) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :release_name, :string, null: false
      add :chart_name, :string, null: false
      add :chart_version, :string
      add :namespace, :string
      add :chart_ref_kind, :string
      add :chart_source, :string
      add :chart_source_namespace, :string
      add :scanner, :string, null: false
      add :icon, :string
      add :group, :string
      add :file_path, :string, null: false
      add :file_url, :string, null: false
      add :lines, :integer, null: false, default: 0
      add :commit_ts, :utc_datetime

      # JSON-encoded values blob. Kept inline for a single-table read path.
      add :values, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:helm_releases, [:chart_name])
    create index(:helm_releases, [:source_id])
    create index(:helm_releases, [:scanner])
    create index(:helm_releases, [:namespace])
    create index(:helm_releases, [:commit_ts])
  end
end
