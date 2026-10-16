import { reactive } from 'vue'
import { api, initConfig } from './api.js'

export const ui = reactive({
  search: '',
  theme: localStorage.getItem('helmscout-theme') || 'dark',
  home: null,
  ready: false,
  error: null,
  values: { open: false, loading: false, title: '', subtitle: '', yaml: null, error: null }
})

export function setTheme(theme) {
  ui.theme = theme
  localStorage.setItem('helmscout-theme', theme)
}

export function homeData() {
  return ui.home
}

// Load the runtime API base, then the small home payload (stats + top apps +
// discover pool).
export async function init() {
  await initConfig()

  try {
    ui.home = await api.home()
  } catch (e) {
    ui.error = String(e)
    console.error(e)
  } finally {
    ui.ready = true
  }
}

export function focusSearch() {
  const el = document.getElementById('global-search')
  if (el) {
    const input = el.querySelector('input') || el
    input.focus?.()
    input.select?.()
  }
}

export async function openValues(release) {
  ui.values.open = true
  ui.values.title = release.app || release.chart_name || 'values'
  ui.values.subtitle = [release.source?.name, release.namespace || 'default']
    .filter(Boolean)
    .join(' · ')
  ui.values.yaml = null
  ui.values.error = null
  ui.values.loading = true

  try {
    const data = await api.values(release.id)
    ui.values.yaml = data.values ? JSON.stringify(data.values, null, 2) : null
    if (!ui.values.yaml) ui.values.error = 'no inline values indexed for this release'
  } catch (e) {
    ui.values.error = String(e)
  } finally {
    ui.values.loading = false
  }
}

export function closeValues() {
  ui.values.open = false
  ui.values.yaml = null
}
