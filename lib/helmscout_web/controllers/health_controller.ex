defmodule HelmscoutWeb.HealthController do
  @moduledoc false

  use HelmscoutWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
