defmodule Helmscout.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :helmscout,
    adapter: Ecto.Adapters.SQLite3
end
