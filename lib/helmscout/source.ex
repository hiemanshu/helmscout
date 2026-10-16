defmodule Helmscout.Source do
  @moduledoc """
  A public Git repository that we crawl for Kubernetes manifests.

  `key` is the lower-cased `owner/repo` identity used for de-duplication across
  discoverers and forges.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Helmscout.HelmRelease

  @type t :: %__MODULE__{}

  schema "sources" do
    field :key, :string
    field :name, :string
    field :forge, :string, default: "github"
    field :url, :string
    field :branch, :string, default: "main"
    field :stars, :integer, default: 0
    field :pushed_at, :utc_datetime
    field :discoverers, {:array, :string}, default: []
    field :topics, {:array, :string}, default: []
    field :last_indexed_at, :utc_datetime
    field :last_commit_sha, :string
    field :release_count, :integer, default: 0
    # Opted out of the MCP server (see Helmscout.Visibility).
    field :hide_mcp, :boolean, default: false

    has_many :helm_releases, HelmRelease

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(key name url)a

  @optional ~w(forge branch stars pushed_at discoverers topics last_indexed_at last_commit_sha
               release_count hide_mcp)a

  def changeset(source, attrs) do
    source
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:key)
  end

  @doc "Build a stable de-dup key from an `owner/repo` name."
  def build_key(name), do: name |> to_string() |> String.trim() |> String.downcase()
end
