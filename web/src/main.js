import { createApp } from 'vue'
import { createVuetify } from 'vuetify'
import '@mdi/font/css/materialdesignicons.css'
import '@fontsource/fira-code/400.css'
import '@fontsource/fira-code/500.css'
import '@fontsource/fira-code/700.css'
import 'vuetify/styles'
import './styles.css'

import App from './App.vue'
import router from './router.js'
import { themes } from './theme.js'
import { init, ui } from './store.js'

const vuetify = createVuetify({
  theme: { defaultTheme: ui.theme, themes },
  display: {
    mobileBreakpoint: 'sm',
    thresholds: { xs: 0, sm: 640, md: 960, lg: 1280, xl: 1920 }
  }
})

const app = createApp(App).use(router).use(vuetify)

// Mount once the home payload is ready, so the server-rendered home page stays
// on screen instead of flashing a spinner over it.
init().finally(() => app.mount('#app'))
