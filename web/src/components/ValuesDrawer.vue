<template>
  <v-navigation-drawer
    :model-value="ui.values.open"
    location="right"
    temporary
    :width="drawerWidth"
    @update:model-value="closeValues"
  >
    <div class="pa-4 d-flex align-center">
      <div class="flex-grow-1">
        <div class="text-h6">{{ ui.values.title }}</div>
        <div class="text-caption text-medium-emphasis">{{ ui.values.subtitle }}</div>
      </div>
      <v-btn icon="mdi-close" variant="text" @click="closeValues" />
    </div>
    <v-divider />

    <div class="pa-4">
      <div v-if="ui.values.yaml" class="d-flex flex-wrap ga-2 mb-3">
        <v-btn size="small" variant="tonal" prepend-icon="mdi-content-copy" @click="copy">copy</v-btn>
      </div>

      <v-progress-linear v-if="ui.values.loading" indeterminate color="primary" class="mb-3" />
      <v-alert v-if="ui.values.error" type="info" variant="tonal" density="compact">
        {{ ui.values.error }}
      </v-alert>

      <pre v-if="ui.values.yaml" class="yaml"><code v-html="highlighted"></code></pre>
    </div>
  </v-navigation-drawer>
</template>

<script setup>
import { computed } from 'vue'
import { useDisplay } from 'vuetify'
import hljs from 'highlight.js/lib/core'
import jsonLang from 'highlight.js/lib/languages/json'
import 'highlight.js/styles/github-dark.css'
import { ui, closeValues } from '../store.js'

hljs.registerLanguage('json', jsonLang)

const { mobile } = useDisplay()
const drawerWidth = computed(() => (mobile.value ? 320 : 720))

const highlighted = computed(() =>
  ui.values.yaml ? hljs.highlight(ui.values.yaml, { language: 'json' }).value : ''
)

async function copy() {
  if (!ui.values.yaml) return
  await navigator.clipboard.writeText(ui.values.yaml)
}
</script>

<style scoped>
.yaml {
  font-size: 12.5px;
  line-height: 1.5;
  padding: 14px;
  border-radius: 8px;
  overflow: auto;
  max-height: calc(100vh - 220px);
  background: #0d1117;
}
.yaml code {
  background: transparent;
}
</style>
