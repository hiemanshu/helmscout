defmodule Helmscout.Database do
  @moduledoc """
  Fetches the read-only SQLite database at boot.

  The pipeline (run on your self-hosted runner) owns the database; the deployed
  app only reads it. When `HELMSCOUT_DB_URL` is set, that file (raw or gzipped)
  is downloaded to `DATABASE_PATH` **before** the repo starts, so the app boots
  with fresh data and needs no persistent storage of its own.

  Point it at something you already pay for — a Supabase Storage object, a GitHub
  release asset, etc. For assets that need auth (a private repo's release), set
  `HELMSCOUT_DB_TOKEN` and it is sent as a bearer token.
  """

  require Logger

  @sqlite_magic "SQLite format 3\0"

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  @doc false
  def start_link(_opts) do
    maybe_fetch!()
    :ignore
  end

  @doc "Download the database if `:database_url` is configured. Safe to call always."
  @spec maybe_fetch!() :: :ok
  def maybe_fetch! do
    case Application.get_env(:helmscout, :database_url) do
      nil -> :ok
      url -> fetch!(url)
    end
  end

  defp fetch!(url) do
    target = Application.get_env(:helmscout, Helmscout.Repo)[:database]
    Logger.info("fetching database from #{url}")

    case Req.get(url,
           headers: auth_headers(),
           finch: [name: Helmscout.Finch],
           decode_body: false,
           receive_timeout: 180_000
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        data = maybe_gunzip(body)

        if sqlite_file?(data) do
          File.mkdir_p!(Path.dirname(target))
          tmp = target <> ".tmp"
          File.write!(tmp, data)
          File.rename!(tmp, target)

          # A -wal/-shm pair left behind by an unclean shutdown would be replayed
          # over the freshly downloaded database and corrupt it. Drop them.
          File.rm(target <> "-wal")
          File.rm(target <> "-shm")

          Logger.info("database ready at #{target} (#{byte_size(data)} bytes)")
        else
          # Wrong content-type (login page, proxy error, HTML 200 …) — keep the
          # database we already have instead of replacing it with garbage.
          Logger.error(
            "downloaded file is not a SQLite database (magic bytes mismatch); " <>
              "keeping #{target}"
          )
        end

      {:ok, %{status: status}} ->
        Logger.error("could not fetch database: HTTP #{status}; starting with #{target}")

      {:error, reason} ->
        Logger.error("could not fetch database: #{inspect(reason)}; starting with #{target}")
    end

    :ok
  end

  defp auth_headers do
    case System.get_env("HELMSCOUT_DB_TOKEN") do
      nil -> []
      "" -> []
      token -> [{"authorization", "Bearer #{token}"}]
    end
  end

  defp sqlite_file?(data) when byte_size(data) >= 16,
    do: binary_part(data, 0, 16) == @sqlite_magic

  defp sqlite_file?(_data), do: false

  defp maybe_gunzip(<<0x1F, 0x8B, _::binary>> = body), do: :zlib.gunzip(body)
  defp maybe_gunzip(body), do: body
end
