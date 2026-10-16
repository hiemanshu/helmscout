import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vuetify from 'vite-plugin-vuetify'

export default defineConfig({
  plugins: [vue(), vuetify({ autoImport: true })],
  server: {
    port: 5173,
    // Dev: Vite serves the SPA with HMR and forwards the API/MCP to Phoenix.
    proxy: {
      '/api': 'http://localhost:4000',
      '/mcp': 'http://localhost:4000',
      '/health': 'http://localhost:4000'
    }
  },
  build: { chunkSizeWarningLimit: 1600 }
})
