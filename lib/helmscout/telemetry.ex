defmodule Helmscout.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      summary("helmscout.discovery.repos_found.total"),
      summary("helmscout.index.files_scanned.total"),
      summary("helmscout.index.releases_found.total")
    ]
  end

  defp periodic_measurements do
    []
  end
end
