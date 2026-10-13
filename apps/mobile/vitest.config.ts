import { fileURLToPath } from 'node:url'
import { defineVitestProject } from '@nuxt/test-utils/config'
import { defineConfig } from 'vitest/config'

const r = (p: string) => fileURLToPath(new URL(p, import.meta.url))

const nuxtProject = await defineVitestProject({
  test: {
    name: 'nuxt',
    include: ['test/nuxt/*.{test,spec}.ts'],
    environment: 'nuxt',
    server: {
      deps: {
        // Konsta ships Vue source files; transform them in Vite instead of
        // loading the package directly through Node during initial navigation.
        inline: ['konsta'],
      },
    },
    sequence: {
      setupFiles: 'list',
      hooks: 'list',
    },
  },
})

// Add our hook after Nuxt's resolved app-entry setup. Passing setupFiles to
// defineVitestProject would prepend it before that entry during config merging.
const nuxtSetupFiles = nuxtProject.test?.setupFiles ?? []
nuxtProject.test!.setupFiles = [
  ...(Array.isArray(nuxtSetupFiles) ? nuxtSetupFiles : [nuxtSetupFiles]),
  r('./test/setup-nuxt.ts'),
]

export default defineConfig({
  test: {
    projects: [
      {
        resolve: {
          alias: {
            '~': r('./app'),
            '~/': r('./app/'),
            '~~': r('.'),
            '~~/': r('./'),
          },
        },
        test: {
          name: 'unit',
          include: ['test/unit/*.{test,spec}.ts'],
          environment: 'node',
          setupFiles: ['test/setup.ts'],
        },
      },
      nuxtProject,
    ],
  },
})
