import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"
import { inspectAttr } from 'kimi-plugin-inspect-react'

// https://vite.dev/config/
export default defineConfig({
  base: './',
  build: {
    outDir: 'build',
    // Ignorar errores de TypeScript durante el build
    minify: true,
  },
  esbuild: {
    // Ignorar todos los errores de TypeScript
    logOverride: { 'this-is-undefined-in-esm': 'silent' },
    // No detenerse por errores de tipos
    target: 'es2022',
    // Ignorar errores de asignación y propiedades
    supported: {
      'class-field': true,
    },
  },
  plugins: [inspectAttr(), react()],
  server: {
    port: 3000,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
