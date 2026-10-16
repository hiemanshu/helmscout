defmodule Helmscout.Prerender do
  @moduledoc """
  Injects server-rendered HTML for the home page into the built `index.html`.

  The home page is the one route worth having in the initial HTML: it is what
  crawlers and first-time visitors see. Everything else (search, app pages,
  sources, stats) stays client-side over SQLite.

  The markup is dropped inside `<div id="app">`, so it paints immediately and is
  then replaced by Vue on hydration. It uses the same Tokyo Night palette, so
  there is no flash of differently-styled content.
  """

  alias Helmscout.Search

  @spec home(Path.t()) :: :ok
  def home(dist_dir) do
    index = Path.join(dist_dir, "index.html")
    html = File.read!(index)

    updated =
      String.replace(
        html,
        ~r{<div id="app">\s*</div>},
        ~s(<div id="app">#{render_home()}</div>),
        global: false
      )

    if updated == html do
      raise "mount point <div id=\"app\"></div> not found in #{index}"
    end

    File.write!(index, updated)
    :ok
  end

  # --- rendering --------------------------------------------------------------

  @doc false
  def render_home do
    apps = Search.top_apps(20)
    discover = Search.discover_pool(1, 6) |> Enum.take_random(5)

    """
    <style>
      html, body { background: #1a1b26; color: #c0caf5; }
      .hs-home { padding: 16px; }
      .hs-home h1, .hs-home h2 { font-size: 1.1rem; font-weight: 700; margin: 0 0 16px; }
      .hs-home section + section { margin-top: 32px; }
      .hs-grid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 14px; }
      @media (max-width: 1100px) { .hs-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
      @media (max-width: 640px) { .hs-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; } }
      .hs-card {
        display: flex; flex-direction: column; gap: 6px; min-height: 92px;
        padding: 16px; border-radius: 12px; text-decoration: none; color: inherit;
        background: rgba(122, 162, 247, 0.12);
        border: 1px solid rgba(192, 202, 245, 0.12);
      }
      .hs-name { font-size: 1.05rem; font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .hs-sub { font-size: 12px; opacity: 0.65; }
    </style>
    <div class="hs-home">
      <section>
        <h1>most deployed apps</h1>
        <div class="hs-grid">
    #{Enum.map_join(apps, "\n", &card/1)}
        </div>
      </section>
      <section>
        <h2>discover something new</h2>
        <div class="hs-grid">
    #{Enum.map_join(discover, "\n", &discover_card/1)}
        </div>
      </section>
    </div>
    """
  end

  defp card(%{app: app, releases: installs, sources: repos}) do
    link(app, "#{installs} installs · #{repos} repos")
  end

  defp discover_card(%{app: app, releases: installs}) do
    link(app, "only #{installs} installs so far")
  end

  defp link(app, sub) do
    ~s(    <a class="hs-card" href="/app/#{URI.encode(to_string(app))}"><span class="hs-name">#{esc(app)}</span><span class="hs-sub">#{esc(sub)}</span></a>)
  end

  defp esc(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
