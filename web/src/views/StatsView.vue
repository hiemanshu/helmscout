<template>
  <div class="pa-2 pa-md-4">
    <div class="d-flex align-center mb-4">
      <h2 class="text-h6 font-weight-bold mb-0">statistics</h2>
      <v-spacer />
      <span class="text-caption text-medium-emphasis">indexed {{ fmtDate(stats.last_indexed_at) }}</span>
    </div>

    <v-row dense>
      <v-col v-for="card in cards" :key="card.label" cols="6" md="3">
        <v-card variant="flat" color="surface" class="pa-4 stat-card">
          <v-icon :icon="card.icon" color="primary" size="22" class="mb-2" />
          <div class="text-h5 font-weight-bold">{{ card.value }}</div>
          <div class="text-caption text-medium-emphasis">{{ card.label }}</div>
        </v-card>
      </v-col>
    </v-row>

    <v-row dense class="mt-2">
      <v-col cols="12" md="6">
        <v-card variant="flat" color="surface" class="pa-4">
          <div class="text-subtitle-2 mb-3">manifest scanners</div>
          <div v-for="s in stats.scanners" :key="s.scanner" class="d-flex align-center ga-3 mb-2">
            <span class="text-body-2" style="min-width: 170px">{{ s.scanner }}</span>
            <v-progress-linear :model-value="pct(s.count)" color="primary" height="8" rounded />
            <span class="text-caption" style="min-width: 60px; text-align: right">{{ s.count.toLocaleString() }}</span>
          </div>
        </v-card>

        <v-card variant="flat" color="surface" class="pa-4 mt-4">
          <div class="text-subtitle-2 mb-3">forge coverage</div>
          <div v-for="f in stats.forges" :key="f.forge" class="d-flex align-center ga-3 mb-2">
            <span class="text-body-2" style="min-width: 170px; text-transform: capitalize">{{ f.forge }}</span>
            <v-progress-linear :model-value="pct(f.count, forgeTotal)" color="secondary" height="8" rounded />
            <span class="text-caption" style="min-width: 60px; text-align: right">{{ f.count.toLocaleString() }}</span>
          </div>
        </v-card>
      </v-col>

      <v-col cols="12" md="6">
        <v-card variant="flat" color="surface" class="pa-4">
          <div class="text-subtitle-2 mb-3">top charts</div>
          <v-table density="compact">
            <tbody>
              <tr v-for="c in charts" :key="c.chart">
                <td>
                  <router-link :to="`/app/${encodeURIComponent(c.chart)}`" class="text-decoration-none">{{ c.chart }}</router-link>
                </td>
                <td class="text-right">{{ c.releases }}</td>
                <td class="text-right text-medium-emphasis">{{ c.sources }} repos</td>
              </tr>
            </tbody>
          </v-table>
        </v-card>
      </v-col>
    </v-row>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../api.js'

const stats = ref({ scanners: [], forges: [] })
const charts = ref([])

const cards = computed(() => [
  { label: 'repositories', value: (stats.value.sources || 0).toLocaleString(), icon: 'mdi-source-repository' },
  { label: 'releases', value: (stats.value.releases || 0).toLocaleString(), icon: 'mdi-package-variant' },
  { label: 'charts', value: (stats.value.charts || 0).toLocaleString(), icon: 'mdi-chart-donut' },
  { label: 'apps', value: (stats.value.apps || 0).toLocaleString(), icon: 'mdi-apps' }
])

const total = computed(() => stats.value.releases || 1)
const forgeTotal = computed(() => (stats.value.forges || []).reduce((a, b) => a + b.count, 0) || 1)
const pct = (count, of) => Math.round((count / (of || total.value)) * 100)
const fmtDate = (v) => (v ? String(v).slice(0, 10) : '—')

onMounted(async () => {
  try {
    const [s, c] = await Promise.all([api.stats(), api.charts({ limit: 15 })])
    stats.value = s
    charts.value = c.charts
  } catch (e) {
    console.error(e)
  }
})
</script>

<style scoped>
.stat-card {
  border-radius: 10px;
}
</style>
