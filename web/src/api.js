// Thin client for the helmscout JSON API.
//
// The frontend is deployed statically, separately from the API, so the base URL
// is resolved at runtime from `/config.json` (written at deploy time), falling
// back to same-origin (local dev / single-host).

let apiBase = ''

export async function initConfig() {
  try {
    const res = await fetch('/config.json', { headers: { accept: 'application/json' } })
    if (res.ok) {
      const config = await res.json()
      apiBase = (config.apiBase || '').replace(/\/$/, '')
    }
  } catch {
    // no config.json — same origin
  }
}

export async function getJSON(path) {
  const res = await fetch(`${apiBase}${path}`, { headers: { accept: 'application/json' } })
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`)
  return res.json()
}

/** Absolute URL for the MCP JSON-RPC endpoint. The protocol lives at
 *  `/api/mcp` on the API host; `/mcp` on the site is the SPA docs page. */
export function mcpUrl() {
  return `${apiOrigin()}/api/mcp`
}

/** Origin of the API (for docs/links). */
export function apiOrigin() {
  return apiBase || window.location.origin
}

function qs(params = {}) {
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') search.set(key, value)
  }
  const query = search.toString()
  return query ? `?${query}` : ''
}

export const api = {
  home: () => getJSON('/api/home'),
  stats: () => getJSON('/api/stats'),
  charts: (params) => getJSON(`/api/charts${qs(params)}`),
  apps: (params) => getJSON(`/api/apps${qs(params)}`),
  app: (app) => getJSON(`/api/apps/${encodeURIComponent(app)}`),
  recommendations: (app) => getJSON(`/api/apps/${encodeURIComponent(app)}/recommendations`),
  releases: (params) => getJSON(`/api/releases${qs(params)}`),
  values: (id) => getJSON(`/api/releases/${id}/values`),
  sources: (params) => getJSON(`/api/sources${qs(params)}`),
  random: () => getJSON('/api/random')
}
