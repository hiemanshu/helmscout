defmodule Helmscout.HelmRelease do
  @moduledoc """
  A single Helm release declaration found in a source repository.

  `scanner` records which manifest shape produced it (Flux `HelmRelease`,
  Argo `Application`, ...). `values` holds the JSON-encoded values object when
  it was inlined in the manifest.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Helmscout.Source

  @type t :: %__MODULE__{}

  schema "helm_releases" do
    field :release_name, :string
    field :chart_name, :string
    field :chart_version, :string
    field :namespace, :string
    field :chart_ref_kind, :string
    field :chart_source, :string
    field :chart_source_namespace, :string
    field :scanner, :string
    field :icon, :string
    field :group, :string
    field :file_path, :string
    field :file_url, :string
    field :lines, :integer, default: 0
    field :commit_ts, :utc_datetime
    field :values, :string
    field :app, :string
    field :images, :string

    belongs_to :source, Source

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(source_id release_name chart_name chart_version namespace chart_ref_kind
             chart_source chart_source_namespace scanner icon group file_path file_url
             lines commit_ts values app images)a

  def changeset(release, attrs) do
    release
    |> cast(attrs, @fields)
    |> validate_required(~w(source_id release_name chart_name scanner file_path file_url)a)
  end

  @doc "Decode the stored `values` JSON, returning `nil` when absent/invalid."
  def decoded_values(%__MODULE__{values: nil}), do: nil

  def decoded_values(%__MODULE__{values: values}) do
    case Jason.decode(values) do
      {:ok, decoded} -> decoded
      _ -> nil
    end
  end
end
