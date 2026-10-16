defmodule Mix.Tasks.Helmscout.Fetch do
  @shortdoc "Clone/update the working trees of discovered sources"
  @moduledoc """
  Materialises every source into the cache directory (`data/repos` by default)
  without indexing. Shows a live progress bar (a per-repo log is written to
  `log/`).

      mix helmscout.fetch
      mix helmscout.fetch --limit 20
      mix helmscout.fetch --concurrency 16
  """

  use Mix.Task

  import Ecto.Query

  @requirements ["app.start"]

  @impl true
  def run(args) do
    Helmscout.Tasks.ensure_database!()

    {opts, _, _} =
      OptionParser.parse(args, strict: [limit: :integer, concurrency: :integer])

    sources = sources(opts[:limit])
    concurrency = opts[:concurrency] || System.schedulers_online()

    progress = Helmscout.Progress.start("fetch", length(sources))

    sources
    |> Task.async_stream(&checkout/1,
      max_concurrency: concurrency,
      timeout: 600_000,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.reduce(progress, fn item, progress ->
      result = normalize(item)
      Helmscout.Progress.update(progress, result, detail(result))
      progress
    end)
    |> Helmscout.Progress.finish()
  end

  defp checkout(source) do
    started = System.monotonic_time(:millisecond)

    result =
      case Helmscout.Fetch.checkout(source) do
        {:ok, _dir} -> %{status: :ok}
        {:error, reason} -> %{status: :error, reason: reason}
      end

    Map.merge(result, %{
      name: source.name,
      duration_ms: System.monotonic_time(:millisecond) - started
    })
  rescue
    e -> %{status: :error, name: source.name, reason: e, duration_ms: 0}
  end

  defp normalize({:ok, result}), do: result

  defp normalize({:exit, reason}),
    do: %{status: :error, name: "?", reason: reason, duration_ms: 0}

  defp detail(%{status: :ok, name: name} = r), do: "ok    #{name} (#{r[:duration_ms]}ms)"
  defp detail(%{status: :error, name: name} = r), do: "error #{name} -> #{inspect(r[:reason])}"

  defp sources(nil), do: all_sources()
  defp sources(limit), do: all_sources() |> Enum.take(limit)

  defp all_sources do
    Helmscout.Repo.all(from s in Helmscout.Source, order_by: [desc: s.stars])
  end
end
