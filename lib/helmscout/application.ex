defmodule Helmscout.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Helmscout.Telemetry,
      {Phoenix.PubSub, name: Helmscout.PubSub},
      {Finch,
       name: Helmscout.Finch,
       pools: %{
         default: [size: 25, count: 1, protocols: [:http2, :http1]]
       }},
      # Fetches the read-only database (if configured) before Repo opens it.
      Helmscout.Database,
      Helmscout.Repo,
      HelmscoutWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Helmscout.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HelmscoutWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
