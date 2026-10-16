defmodule Helmscout.Scanner do
  @moduledoc """
  Behaviour for manifest scanners.

  A scanner knows how to recognise one manifest shape and extract a Helm release
  from it. `pre_check?/1` is a cheap substring test used to avoid YAML-parsing
  every file in a repository.
  """

  @typedoc "Release attributes extracted from a manifest (no file/source metadata)."
  @type release :: %{
          optional(:release_name) => String.t() | nil,
          optional(:chart_name) => String.t() | nil,
          optional(:chart_version) => String.t() | nil,
          optional(:namespace) => String.t() | nil,
          optional(:chart_ref_kind) => String.t() | nil,
          optional(:chart_source) => String.t() | nil,
          optional(:chart_source_namespace) => String.t() | nil,
          optional(:icon) => String.t() | nil,
          optional(:group) => String.t() | nil,
          optional(:values) => String.t() | nil
        }

  @callback name() :: String.t()
  @callback pre_check?(binary()) :: boolean()

  @doc """
  Extract release(s) from a document.

  Returns `{:ok, release}` for a single release, `{:ok, [release]}` when a
  manifest expands into several (e.g. an Argo `ApplicationSet` with a list
  generator), or `:skip`.
  """
  @callback parse(Helmscout.Manifest.doc()) :: {:ok, release() | [release()]} | :skip

  @doc "All scanners, in the order they are applied."
  @spec all() :: [module()]
  def all do
    [
      Helmscout.Scanners.FluxHelmRelease,
      Helmscout.Scanners.ArgoApplication,
      Helmscout.Scanners.ArgoApplicationSet
    ]
  end
end
