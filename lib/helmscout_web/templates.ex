defmodule HelmscoutWeb.Templates do
  @moduledoc """
  Compile-time EEx templates for the small server-rendered UI.

  Using plain EEx (rather than a full view layer) keeps the web side dependency
  free while still escaping all user-controlled output.
  """

  require EEx

  EEx.function_from_file(
    :def,
    :layout_html,
    Path.expand("templates/layout.html.eex", __DIR__),
    [:assigns]
  )

  EEx.function_from_file(
    :def,
    :search_html,
    Path.expand("templates/search.html.eex", __DIR__),
    [:assigns]
  )

  EEx.function_from_file(
    :def,
    :chart_html,
    Path.expand("templates/chart.html.eex", __DIR__),
    [:assigns]
  )

  @doc "Render a page (search or chart) wrapped in the shared layout."
  def render(body_fun, assigns) when is_function(body_fun, 1) do
    layout_html(Map.put(assigns, :body, body_fun.(assigns)))
  end

  @doc "HTML-escape a value for safe interpolation."
  def esc(nil), do: ""

  def esc(value) do
    value |> to_string() |> Plug.HTML.html_escape()
  end

  @doc "URL-encode a path segment."
  def url(value), do: URI.encode(to_string(value))

  @doc "Format a DateTime for display."
  def fmt(nil), do: "—"

  def fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  def fmt(other), do: to_string(other)
end
