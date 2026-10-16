<template>
  <v-app :theme="ui.theme">
    <v-navigation-drawer v-model="drawer" :permanent="!mobile" :temporary="mobile" width="248">
      <router-link to="/" class="brand" @click="mobile && (drawer = false)">
        <v-icon icon="mdi-kubernetes" color="primary" size="26" />
        <span>helmscout</span>
      </router-link>
      <v-divider />
      <v-list nav density="comfortable">
        <v-list-item
          v-for="item in nav"
          :key="item.to"
          :to="item.to"
          :prepend-icon="item.icon"
          :title="item.title"
          exact
        />
        <v-list-item prepend-icon="mdi-dice-multiple" title="discover" @click="discover" />
      </v-list>
      <template #append>
        <v-divider />
        <div v-if="stats" class="pa-3 text-caption text-medium-emphasis">
          <div>{{ fmt(stats.releases) }} releases</div>
          <div>{{ fmt(stats.charts) }} charts</div>
          <div>{{ fmt(stats.sources) }} repositories</div>
        </div>
      </template>
    </v-navigation-drawer>

    <v-app-bar flat color="surface" density="comfortable" :elevation="0" class="border-b">
      <v-app-bar-nav-icon v-if="mobile" @click="drawer = !drawer" />
      <v-app-bar-title class="d-none d-sm-flex" style="max-width: 140px">
        <router-link to="/" class="brand-link">helmscout</router-link>
      </v-app-bar-title>

      <v-text-field
        id="global-search"
        v-model="ui.search"
        class="mx-2"
        density="comfortable"
        variant="solo-filled"
        flat
        hide-details
        clearable
        prepend-inner-icon="mdi-magnify"
        placeholder="search apps, charts, releases… (ctrl-k)"
        @update:model-value="onSearchInput"
      />

      <v-tooltip text="surprise me" location="bottom">
        <template #activator="{ props }">
          <v-btn v-bind="props" icon="mdi-dice-multiple" @click="discover" />
        </template>
      </v-tooltip>

      <v-btn :icon="ui.theme === 'dark' ? 'mdi-weather-sunny' : 'mdi-weather-night'" @click="toggleTheme" />
    </v-app-bar>

    <v-main>
      <v-alert
        v-if="ui.error"
        type="error"
        variant="tonal"
        class="ma-4"
        :text="ui.error"
        title="could not load the index"
      />
      <router-view v-else-if="ui.ready" />
      <div v-else class="d-flex flex-column align-center justify-center" style="min-height: 60vh">
        <v-progress-circular indeterminate color="primary" size="48" />
        <div class="mt-4 text-medium-emphasis">loading…</div>
      </div>
    </v-main>

    <ValuesDrawer />
  </v-app>
</template>

<script setup>
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useDisplay } from 'vuetify'
import { api } from './api.js'
import { ui, setTheme, focusSearch, homeData } from './store.js'
import ValuesDrawer from './components/ValuesDrawer.vue'

const router = useRouter()
const { mobile } = useDisplay()
const drawer = ref(!mobile.value)

const nav = [
  { to: '/', title: 'search', icon: 'mdi-magnify' },
  { to: '/sources', title: 'repositories', icon: 'mdi-source-repository' },
  { to: '/stats', title: 'statistics', icon: 'mdi-chart-box-outline' },
  { to: '/mcp', title: 'mcp', icon: 'mdi-robot-outline' },
  { to: '/about', title: 'about', icon: 'mdi-information-outline' }
]

const stats = computed(() => homeData()?.stats)
const fmt = (n) => (n ?? 0).toLocaleString()

function toggleTheme() {
  setTheme(ui.theme === 'dark' ? 'light' : 'dark')
}

function onSearchInput() {
  if (router.currentRoute.value.name !== 'search') router.push('/')
}

async function discover() {
  try {
    const pick = await api.random()
    if (pick.type === 'app' && pick.value) router.push(`/app/${encodeURIComponent(pick.value)}`)
    else if (pick.type === 'source' && pick.value) router.push({ path: '/', query: { source: pick.value } })
  } catch (e) {
    console.error(e)
  }
}

function onKeydown(e) {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
    e.preventDefault()
    focusSearch()
  }
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>

<style>
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 18px 16px;
  text-decoration: none;
  color: inherit;
}
.brand-link {
  text-decoration: none;
  color: inherit;
}
.border-b {
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}
</style>
