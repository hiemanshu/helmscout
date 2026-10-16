defmodule Helmscout.Repo.Migrations.AddAppAndImagesToHelmReleases do
  use Ecto.Migration

  def change do
    alter table(:helm_releases) do
      # Best-guess application name (resolves generic charts like app-template
      # to the real app, e.g. "immich").
      add :app, :string

      # JSON array of container image repositories found in the values.
      add :images, :text
    end

    create index(:helm_releases, [:app])
  end
end
