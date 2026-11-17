import { addComponent, addImports, defineNuxtModule } from '@nuxt/kit'

const components = [
  'Alert',
  'App',
  'Avatar',
  'BackButton',
  'Badge',
  'Button',
  'Buttons',
  'CardContent',
  'Chip',
  'Content',
  'Header',
  'Icon',
  'InfiniteScroll',
  'InfiniteScrollContent',
  'Input',
  'Item',
  'ItemOption',
  'ItemOptions',
  'ItemSliding',
  'Label',
  'List',
  'Modal',
  'Note',
  'Page',
  'Popover',
  'Refresher',
  'RefresherContent',
  'RouterOutlet',
  'Searchbar',
  'Segment',
  'SegmentButton',
  'Select',
  'SelectOption',
  'Spinner',
  'TabBar',
  'TabButton',
  'Tabs',
  'Textarea',
  'Title',
  'Toolbar',
]

export default defineNuxtModule({
  setup(_options, nuxt) {
    for (const component of components) {
      const name = `Ion${component}`
      addComponent({ name, export: name, filePath: '@ionic/vue' })
    }
    addImports({ name: 'alertController', from: '@ionic/vue' })
    nuxt.options.build.transpile.push(/@ionic/, /@stencil/, /ionicons/)
    // Keep Nuxt routing and middleware. Only substitute the factory that installs
    // Ionic's navigation manager and outlet stacks onto the same Vue Router.
    nuxt.hook('vite:extendConfig', (config) => {
      const plugins = config.plugins
      if (!plugins)
        throw new Error('Nuxt Vite plugins must be initialized before Ionic routing')
      plugins.push({
        name: 'yunlefun:ionic-router-factory',
        enforce: 'pre',
        async resolveId(source, importer) {
          if (source === 'vue-router' && importer?.replaceAll('\\', '/').endsWith('/nuxt/dist/pages/runtime/plugins/router.js'))
            return this.resolve('~/compat/ionic-router', importer, { skipSelf: true })
        },
      })
    })
    nuxt.hook('app:resolve', (app) => {
      // This app intentionally renders IonRouterOutlet instead of NuxtPage.
      const index = app.plugins.findIndex(plugin => plugin.src.includes('/check-if-page-unused'))
      if (index >= 0)
        app.plugins.splice(index, 1)
    })
  },
})
