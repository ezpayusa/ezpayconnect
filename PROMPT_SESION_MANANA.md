# 🤖 Prompt para sesión de desarrollo — EzPayConnect

> **INSTRUCCIÓN INICIAL:** Lee el archivo `ESTADO_PROYECTO_EZPAYCONNECT.md` antes de cualquier acción. Contiene el estado completo del proyecto, lo que está implementado y lo que falta. Úsalo como fuente de verdad.

---

## 🏗️ Stack del proyecto

- **Frontend:** React 19 + TypeScript + Vite 6 + Tailwind CSS v4 + shadcn/ui
- **Backend:** Supabase Auth + PostgreSQL + Edge Functions (Deno runtime)
- **Routing:** React Router v7 (rutas padre con hijos anidados DEBEN terminar en `/*`)
- **Mapas:** Leaflet + OpenStreetMap (gratuito, sin API key)
- **PWA:** vite-plugin-pwa con workbox (Service Worker cachea agresivamente)
- **Email:** Resend API
- **AI:** OpenAI GPT-4o-mini + Whisper
- **Deploy:** Vercel (`https://ezpayconnect.vercel.app`)
- **Supabase Project:** `fqnsmvkxsuujahhmpzuk` (West US)

---

## 📂 Estructura clave

```
src/
  pages/                    → Panel médico principal + admin-ezpay + planes + reportes
  components/consulta/      → Componentes de consulta médica
  components/layout/        → Sidebar, navegación
  hooks/                    → Hooks de Supabase (useAuth, useCitas, usePacientes, etc.)
  types/                    → Tipos centralizados
  proveedor/                → Portal de proveedores (farmaceuticos/labs)
  webapp/                   → Portal público para pacientes
  clinica/                  → Panel de clínica
  lib/metricas/             → Métricas y campañas

supabase/
  functions/                → Edge Functions (Deno)
  migrations/               → Migraciones SQL (28 migraciones, ~3,297 líneas)
```

---

## ✅ Estado actual (resumen)

**~90% del MVP está implementado y funcional.** Los 3 portales (médico, proveedor, paciente) están operativos con datos reales. Consulta `ESTADO_PROYECTO_EZPAYCONNECT.md` para el detalle completo.

### Lo que YA funciona
- Panel médico: consulta SOAP, recetas, signos vitales, IA, biblioteca, dashboard, facturas, reportes
- Portal proveedores: visitadores, check-in/out GPS, rutas, campañas, pagos, notificaciones badge
- Portal paciente: citas, recetas, exámenes, chat, historial médico, perfil, notificaciones
- Panel clínica: dashboard, personal, invitaciones
- Admin maestro: países, usuarios, planes por país, campañas, finanzas, RLS
- Infraestructura: 29 Edge Functions, 28 migraciones, PWA, cron-job.org

---

## 🔴 PENDIENTES CRÍTICOS (en orden de prioridad)

### 1. Verificar dominio en Resend (infraestructura externa)
- **Estado:** Ticket enviado a Asura Hosting. Esperando modificación de SPF + DMARC.
- **Acción si Asura confirmó:** Click "Verify" en Resend dashboard → revertir `from` a `no-reply@ezpayconnect.com` en Edge Functions
- **Archivos:** `supabase/functions/notificar-email/index.ts`, `supabase/functions/procesar-recordatorios/index.ts`
- **Deploy:** `npx supabase functions deploy notificar-email procesar-recordatorios`

### 2. Revisar logs de `procesar-recordatorios`
- **Dónde:** Supabase Dashboard → Edge Functions → Logs
- **Qué buscar:** Errores silenciosos cada 15 min
- **Acción:** Corregir bugs encontrados

### 3. Verificar cron-job.org
- **Dónde:** https://cron-job.org/
- **Qué verificar:** Job `POST procesar-recordatorios` sigue activo, toggle "Disable after failures" = ON

---

## 🟡 PRÓXIMAS TAREAS DE DESARROLLO (elegir una o más)

### Opción A — Agendar citas desde portal del paciente (Alta prioridad)
El botón "Agendar cita" en `WebAppDashboard.tsx` no tiene acción. Implementar:
- Página/Modal de agendado: seleccionar médico/clínica → fecha → hora → motivo
- Guardar en tabla `citas` con estado `pendiente`
- Notificación al médico/clínica
- Edge Function `programar-recordatorio` automático

### Opción B — Notificaciones push del navegador (Media prioridad)
- Service Worker: agregar manejo de Push API
- Tabla `push_subscriptions` (nueva migración)
- Edge Function para enviar push (usar web-push)
- Solicitar permiso al usuario en login

### Opción C — Segmentación contextual por ruta GPS (Media prioridad)
En campañas publicitarias del portal proveedor:
- Filtrar visualización de campañas por ubicación GPS del médico
- Usar coordenadas de `medicos.lat`, `medicos.lng`
- Mostrar solo campañas de farmacias/labs dentro de X km

### Opción D — Code splitting y optimización de bundle (Baja prioridad)
- Bundle principal es 2.2 MB
- Implementar `React.lazy()` + `Suspense` para:
  - Panel de proveedores
  - Portal del paciente
  - Reportes
- Meta: bundle inicial < 1 MB

### Opción E — Offline support para check-in de visitador (Baja prioridad)
- Si no hay conexión: guardar foto + GPS en IndexedDB
- Cuando recupera conexión: sync automático a Supabase
- Mostrar estado "Pendiente de sincronización" en UI

### Opción F — Deuda técnica (Baja prioridad)
- Migrar `enviar-recordatorio` (usa tabla `recordatorios_citas` legacy) a tabla `recordatorios`
- Crear vistas faltantes: `v_pacientes_actividad`, `v_resumen_mensual`, `v_estadisticas_medico`
- Limpiar tabla `paises` legacy (reemplazada por `configuracion_pais`)

---

## 🔐 Reglas de código y convenciones

- **Feedback al usuario:** Usar `toast` de `sonner` para errores y éxito
- **Supabase embedded queries (joins) FALLAN** en este proyecto. Siempre usar queries separadas secuenciales
- **Edge Functions:** NO pueden llamarse entre sí vía `fetch` + `serviceRoleKey` (devuelve 401). Solución: llamar API externa directa o escribir a DB
- **Migraciones SQL:** Usar `IF NOT EXISTS` para tablas/índices. Para policies: `DROP POLICY IF EXISTS` + `CREATE POLICY`
- **RLS policies:** Verificar `auth.uid()` y roles. Patrón: `super_admin` ve todo, `admin_pais` solo su país
- **React Router v7:** Rutas padre con hijos anidados DEBEN terminar en `/*`
- **Dictado por voz:** NUNCA usar `webkitSpeechRecognition`. Siempre usar MediaRecorder + Whisper Edge Function
- **Fechas:** Usar `date-fns` con locale `es`
- **Build:** `npm run build` → verificar sin errores → `npx vercel --prod --yes`
- **Edge Functions deploy:** `npx supabase functions deploy <nombre>`
- **PWA testing:** Siempre usar Ctrl+F5 o incógnito para probar cambios recientes
- **País default:** Guatemala (`cbbbbe6d-59fe-4cf2-91ee-3e31ba1d5909`)
- **Filtrado por país:** Usar `usePaisFiltro()` que determina automáticamente `pais_id` según contexto

---

## 🚀 Flujos críticos que deben seguir funcionando

### Panel médico
1. Citas → clic "Atender" → `/consulta/:citaId`
2. Nota SOAP → guardar → crea/actualiza `expediente_notas`
3. Signos vitales → se guardan en `signos_vitales` + IMC calculado por trigger
4. Dictado por voz → clic Dictar → hablar → clic Detener → Whisper transcribe
5. Receta → clic "Nueva Receta" → crear receta
6. Factura → crear → vista previa → enviar/descargar

### Portal proveedores
1. Visitador propone visita → trigger `estado = 'propuesta'`
2. Admin aprueba → `estado = 'confirmada'` + consume crédito
3. Visitador check-in → foto + GPS en `evidencias-visitas`
4. Visitador check-out → visita `completada`

### Portal paciente
1. Login → dashboard con contadores reales
2. Citas → tabs Próximas/Pasadas/Canceladas
3. Chat → mensaje en tiempo real
4. Perfil → editar → guardar → recargar

---

## 📋 Checklist antes de empezar a codear

- [ ] Leí `ESTADO_PROYECTO_EZPAYCONNECT.md`
- [ ] Verifiqué si Asura Hosting respondió sobre DNS Resend
- [ ] Revisé logs de `procesar-recordatorios` en Supabase
- [ ] Confirmé que cron-job.org sigue activo
- [ ] Elegí qué tarea(s) voy a implementar hoy

---

## 🎯 Misión de hoy (indicar al inicio de la sesión)

> "Hoy voy a implementar: [Opción A/B/C/D/E/F] + [verificar Resend si Asura respondió / no]"
