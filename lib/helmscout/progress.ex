defmodule Helmscout.Progress do
  @moduledoc """
  A dependency-free progress reporter for long parallel stages.

  Writes a timestamped, per-item line to a log file (the tail-able source of
  truth) and prints a plain progress line every `step` items (default 50) so a
  run is readable in `mix` output and in CI logs.

  Configure the interval with `HELMSCOUT_PROGRESS_STEP` or the `:step` option.
  """

  defstruct label: "",
            total: 0,
            count: 0,
            ok: 0,
            empty: 0,
            error: 0,
            skipped: 0,
            releases: 0,
            started_at: 0,
            step: 50,
            log: nil,
            log_path: nil

  @type t :: %__MODULE__{}

  @doc "Start tracking. Returns a `t:t/0`; prints the log path to stderr."
  @spec start(String.t(), non_neg_integer(), keyword()) :: t()
  def start(label, total, opts \\ []) do
    log_path = Keyword.get(opts, :log_path) || default_log_path(label)
    File.mkdir_p!(Path.dirname(log_path))
    log = File.open!(log_path, [:write, :utf8])

    state = %__MODULE__{
      label: label,
      total: total,
      started_at: now_ms(),
      step: step(opts),
      log: log,
      log_path: log_path
    }

    IO.puts(:stderr, "#{label}: #{total} items -> log: #{log_path}")
    state
  end

  @doc """
  Record a completed item. `result` is any map; `:status` (`:ok`/`:empty`/`:error`)
  and `:releases` are tallied when present. `detail` is written to the log.
  """
  @spec update(t(), map(), String.t() | nil) :: t()
  def update(%__MODULE__{} = state, result, detail) do
    if is_binary(detail) and state.log, do: IO.write(state.log, log_prefix() <> detail <> "\n")

    state = bump(state, result)

    if state.step > 0 and state.count < state.total and rem(state.count, state.step) == 0 do
      report(state)
    end

    state
  end

  @doc "Print the final summary and close the log."
  @spec finish(t()) :: t()
  def finish(%__MODULE__{} = state) do
    if state.log, do: File.close(state.log)
    IO.puts(:stderr, "#{state.label} done: #{summary(state)}")
    state
  end

  @doc "Path to the run's progress log (useful to print early)."
  def log_path(%__MODULE__{log_path: path}), do: path

  # --- internals --------------------------------------------------------------

  defp bump(state, result) do
    releases = Map.get(result, :releases, 0) || 0
    field = status_field(Map.get(result, :status, :ok))

    state
    |> Map.update!(:count, &(&1 + 1))
    |> Map.update!(:releases, &(&1 + releases))
    |> Map.update!(field, &(&1 + 1))
  end

  defp status_field(:ok), do: :ok
  defp status_field(:empty), do: :empty
  defp status_field(:skipped), do: :skipped
  defp status_field(_), do: :error

  defp report(state) do
    IO.puts(:stderr, "#{state.label}: #{summary(state)}")
  end

  defp step(opts) do
    case Keyword.get(opts, :step) do
      n when is_integer(n) and n > 0 -> n
      _ -> env_step()
    end
  end

  defp env_step do
    case System.get_env("HELMSCOUT_PROGRESS_STEP") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {n, _} when n > 0 -> n
          _ -> 50
        end

      _ ->
        50
    end
  end

  defp summary(state) do
    "#{state.count}/#{state.total} (#{state.ok} ok, #{state.empty} empty, #{state.skipped} skipped, " <>
      "#{state.error} error, #{state.releases} releases, #{elapsed(state)}s)"
  end

  defp elapsed(state), do: Float.round((now_ms() - state.started_at) / 1000, 1)

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp log_prefix do
    Calendar.strftime(DateTime.utc_now(), "[%H:%M:%S] ")
  end

  defp default_log_path(label) do
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    Path.join(Application.get_env(:helmscout, :log_dir, "log"), "#{label}-#{stamp}.log")
  end
end
