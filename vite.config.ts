/// <reference types="vitest/config" />
import path from "path"
import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"
import { VitePWA } from "vite-plugin-pwa"
import { sentryVitePlugin } from "@sentry/vite-plugin"

// Sentry sube sourcemaps SOLO si hay auth token (presente en Vercel prod/preview vía env).
// En local, sin SENTRY_AUTH_TOKEN, el plugin NO se agrega: el build corre igual y no intenta
// subir nada ni rompe. org/project/token se leen de process.env (cargadas en Vercel).
const sentryAuthToken = process.env.SENTRY_AUTH_TOKEN

export default defineConfig({
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    css: false,
  },
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: "autoUpdate",
      strategies: "injectManifest",
      srcDir: "src",
      filename: "sw.ts",
      includeAssets: ["icon.svg", "favicon.ico", "robots.txt"],
      manifest: {
        name: "EzPayConnect - Portal del Paciente",
        short_name: "EzPayConnect",
        description: "Portal del paciente para gestionar citas, recetas, exámenes y comunicación con tu médico.",
        theme_color: "#0ea5e9",
        background_color: "#ffffff",
        display: "standalone",
        scope: "/",
        start_url: "/paciente/dashboard",
        icons: [
          {
            src: "/icon-192x192.png",
            sizes: "192x192",
            type: "image/png",
          },
          {
            src: "/icon-512x512.png",
            sizes: "512x512",
            type: "image/png",
          },
          {
            src: "/icon.svg",
            sizes: "512x512",
            type: "image/svg+xml",
            purpose: "any maskable",
          },
        ],
      },
      injectManifest: {
        globPatterns: ["**/*.{js,css,html,ico,png,svg,woff2}"],
        maximumFileSizeToCacheInBytes: 5242880,
      },
      devOptions: {
        enabled: true,
        type: "module",
        navigateFallback: "index.html",
      },
    }),
    // Debe ir DESPUÉS del resto de plugins: opera sobre el output final.
    // Sourcemaps a Sentry. Solo se activa con SENTRY_AUTH_TOKEN (Vercel prod/preview);
    // en local no corre.
    //   - telemetry: false → decisión explícita, no mandamos telemetría del build.
    //   - release: se deja en AUTO a propósito. En Vercel autodetecta el SHA de git y lo
    //     crea en Sentry (por eso el token lleva scope project:releases). Sirve para saber
    //     de qué commit salió cada error. Inyecta SENTRY_RELEASE en el bundle: es un hash
    //     de git, no dato sensible.
    ...(sentryAuthToken
      ? [
          sentryVitePlugin({
            org: process.env.SENTRY_ORG,
            project: process.env.SENTRY_PROJECT,
            authToken: sentryAuthToken,
            telemetry: false,
            sourcemaps: {
              // Tras subir los .map a Sentry, borrarlos del output → no quedan en el bundle público.
              filesToDeleteAfterUpload: ["./dist/**/*.map"],
            },
          }),
        ]
      : []),
  ],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    // 'hidden': genera el .map pero NO deja el comentario //# sourceMappingURL en el bundle.
    // El mapa se sube a Sentry y luego se borra (filesToDeleteAfterUpload); nunca queda expuesto.
    sourcemap: "hidden",
    rollupOptions: {
      output: {
        manualChunks: {
          // Vendor base (siempre cargado)
          "react-vendor": ["react", "react-dom", "react-router-dom"],
          // Librerías pesadas usadas solo por algunas rutas -> chunks bajo demanda
          charts: ["recharts"],
          pdf: ["jspdf", "jspdf-autotable"],
          maps: ["leaflet", "react-leaflet"],
          qr: ["html5-qrcode", "qrcode.react"],
        },
      },
    },
  },
})
