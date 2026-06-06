# 🤖 Prompt para sesión de desarrollo — EzPayConnect

> Copia y pega esto como mensaje inicial al iniciar la sesión con Kimi Code CLI.

---

Hola, soy Kimi Code CLI. Hoy continúo el desarrollo de EzPayConnect.

## 🏗️ Stack del proyecto

- **Frontend:** React 19 + TypeScript + Vite 6 + Tailwind CSS v4 + shadcn/ui
- **Backend:** Supabase Auth + PostgreSQL + Edge Functions (Deno runtime)
- **Routing:** React Router v7 (rutas anidadas requieren `/*` en el padre)
- **Mapas:** Leaflet + OpenStreetMap (gratuito, sin API key)
- **PWA:** vite-plugin-pwa con workbox (Service Worker cachea agresivamente)
- **Deploy:** Vercel (`https://ezpayconnect.vercel.app`)
- **Repo:** `ezpayusa/ezpayconnect`, rama `main`

## 📂 Estructura clave

```
src/
  pages/                    → Páginas principales del panel médico
  components/consulta/      → Componentes de consulta médica
  components/layout/        → Sidebar, navegación
  hooks/                    → Hooks de Supabase (useConsultas, useRecetas, etc.)
  types/                    → Tipos centralizados (Paciente, ExpedienteNota, etc.)
  proveedor/                → Portal de proveedores (farmaceuticos/labs)
  webapp/                   → Portal público para pacientes

supabase/
  functions/                → Edge Functions (Deno)
  migrations/               → Migraciones SQL
```

---

## ✅ Estado actual — Panel Médico Profesional (COMPLETADO)

### Vista de consulta unificada `/consulta/:citaId`
- Layout 3 columnas: info paciente + signos vitales | nota SOAP | acciones + biblioteca + IA
- Estados visuales de citas: pendiente, confirmada, en_curso, completada, cancelada, no_show
- Botón "Atender" en agenda navega a `/consulta/:citaId`

### Nota SOAP (5 pestañas)
- Motivo, Subjetivo, Objetivo, Análisis, Plan
- Guarda en `expediente_notas` con campos SOAP estructurados
- Dictado por voz en cada campo (usa OpenAI Whisper vía Edge Function)

### Signos Vitales estructurados
- PA, FC, FR, Temp, Peso, Talla, SpO2, Glucosa
- Cálculo automático de IMC (triggers SQL)
- Historial temporal en tabla `signos_vitales`

### Dictado por voz
- **NO usa `webkitSpeechRecognition`** (bloqueado por ISP/firewall en Guatemala)
- Usa **MediaRecorder** → graba audio → envía a Edge Function `dictado-voz` → OpenAI Whisper
- Flujo: clic "Dictar" → habla → clic "Detener" → transcribe en 1-2 segundos
- Costo: ~$0.006/minuto de audio

### Biblioteca Médica integrada
- Edge Function `consultar-biblioteca`: PubMed + Wikipedia
- Tabs para cambiar fuente
- Botón "Copiar a nota"

### Asistente de IA
- Edge Function `asistente-ia`: GPT-4o-mini
- Recibe contexto médico completo (signos vitales, SOAP, alergias, etc.)
- Devuelve JSON estructurado: diagnósticos diferenciales, exámenes, opciones farmacológicas, contraindicaciones
- Guarda auditoría en tabla `auditoria_ia`
- Fallback a respuesta mock si OpenAI falla por cuota

### Recetas integradas
- `RecetaModal.tsx` reutilizable (se usa en `/recetas` y dentro de `/consulta`)
- Alertas de alergias del paciente (banner rojo)
- Búsqueda de farmacias/laboratorios por item

### Dashboard médico
- Stats reales: pacientes, citas hoy, recetas, consultas esta semana
- Próximas citas reales
- Links rápidos a consulta, pacientes, recetas, buscar medicamentos

### Paciente detalle
- Tabs nuevos: Consultas, Signos Vitales

---

## ✅ Estado actual — Portal Proveedores (funciona)

- Portal con roles: `admin`, `editor`, `visitador_medico`
- Invitación de visitadores por WhatsApp (token + link de registro)
- Registro de visitadores invitados
- Flujo propuesta → aprobación de visitas (consume créditos del plan)
- Check-in/check-out con foto + GPS (bucket `evidencias-visitas`)
- Ruta del día con mapa Leaflet + navegación a Google Maps / Waze
- Geocodificación (`geocodificar`: Google primero, Nominatim fallback)
- Panel EzPay admin: empresas proveedoras, roles, reportes, campañas publicitarias

---

## ⚠️ Bugs conocidos / pendientes

- [ ] **Service Worker cachea versiones viejas** → siempre hacer hard refresh (Ctrl+Shift+R) o desregistrar SW en DevTools > Application > Service Workers > Unregister
- [ ] `ProveedorPagosPage.tsx` está vacío (placeholder)
- [ ] `ProveedorPerfilPage.tsx` es solo lectura
- [ ] `ProveedorDashboard.tsx` tiene placeholder de estadísticas
- [ ] **Recordatorio 24h antes de visita** — pendiente (requiere cron job o Edge Function programada)
- [ ] Segmentación contextual por ruta de publicidad (Fase 5) — estructura lista pero no filtra aún
- [ ] `PublicidadPlanesPage.tsx` no carga planes desde base de datos (aunque tabla `planes_publicidad` sí existe)

---

## 🎯 Misión de hoy (elegir una o más)

### Opción A — Sistema de notificaciones por email (alta prioridad)
Edge Function `notificar-email` ya existe. Completar flujos:
- Admin recibe email cuando visitador propone visita
- Visitador recibe email cuando admin aprueba/rechaza
- Recordatorio 24h antes de visita confirmada (cron con pg_cron o Edge Function programada)
- Tabla `notificaciones_email` ya existe (migración 019)

### Opción B — Página de Pagos funcional (alta prioridad)
Completar `ProveedorPagosPage.tsx`:
- Historial real desde tabla `pagos_proveedor`
- Comprobantes subidos
- Filtros por estado: pendiente, aprobado, rechazado
- Totales por mes

### Opción C — Perfil editable (media prioridad)
`ProveedorPerfilPage.tsx` editable:
- Formulario para actualizar datos de empresa
- Subir/actualizar logo
- Guardar en `empresas_proveedoras` y `cuentas_proveedor`

### Opción D — Dashboard con estadísticas reales (media prioridad)
Reemplazar placeholder en `ProveedorDashboard.tsx`:
- Visitas este mes / semana
- Tasa de concreción
- Créditos disponibles vs usados
- Campañas publicitarias activas

### Opción E — Recordatorios de visita (media prioridad)
- Email/SMS al visitador 1 hora antes
- Confirmación al médico
- Generar archivo `.ICS` (calendario)

### Opción F — Offline support / PWA robusta (baja prioridad)
- Check-in con foto sin internet → guardar en IndexedDB → sincronizar

---

## 🔐 Acceso y configuración

| Recurso | Valor |
|---------|-------|
| Supabase Project | `fqnsmvkxsuujahhmpzuk` |
| Supabase URL | `https://fqnsmvkxsuujahhmpzuk.supabase.co` |
| Vercel deploy | `https://ezpayconnect.vercel.app` |
| **Secrets de Supabase** | `OPENAI_API_KEY` ✅, `GOOGLE_MAPS_API_KEY` ✅, `RESEND_API_KEY` ✅, `SUPABASE_SERVICE_ROLE_KEY` ✅ |
| **Edge Functions deployadas** | `geocodificar`, `invitar-visitador`, `validar-invitacion`, `notificar-email`, `consultar-biblioteca`, `asistente-ia`, `dictado-voz` |
| Bucket de evidencias | `evidencias-visitas` |

---

## 📋 Reglas de código y convenciones

- **Feedback al usuario:** Usar `toast` de `sonner` para errores y éxito
- **Edge Functions:** Usar `fetch` directo en lugar de `createClient` desde `esm.sh` (propenso a fallos). Para Supabase REST, usar `fetch` con headers `Authorization` + `apikey`
- **Migraciones SQL:** Usar `IF NOT EXISTS` para tablas/índices. Para policies: `DROP POLICY IF EXISTS` + `CREATE POLICY` (NO `IF NOT EXISTS` en policies)
- **RLS policies:** Verificar `auth.uid()` y roles
- **React Router v7:** Rutas padre con hijos anidados **deben** terminar en `/*`
- **Dictado por voz:** NUNCA usar `webkitSpeechRecognition`. Siempre usar MediaRecorder + Whisper Edge Function
- **Fechas:** Usar `date-fns` con locale `es`
- **Build:** `npm run build` → `npx vercel --prod --yes`
- **Edge Functions deploy:** `npx supabase functions deploy <nombre>`

---

## 🚀 Flujos críticos que deben seguir funcionando

### Panel médico
1. Citas → clic "Atender" → `/consulta/:citaId`
2. Nota SOAP → guardar → crea/actualiza `expediente_notas`
3. Signos vitales → se guardan en `signos_vitales` + IMC calculado por trigger
4. Dictado por voz → clic Dictar → hablar → clic Detener → Whisper transcribe → texto insertado
5. Asistente IA → clic "Analizar" → GPT-4o-mini responde → sugerencias mostradas
6. Receta → clic "Nueva Receta" → RecetaModal se abre → crear receta

### Portal proveedores
1. Visitador propone visita → trigger `estado = 'propuesta'`
2. Admin aprueba → `estado = 'confirmada'` + consume crédito
3. Visitador check-in → foto + GPS en `evidencias-visitas`
4. Visitador check-out → visita `completada`

---

**Por favor indícame qué opción(es) vas a implementar hoy y hazme cualquier pregunta antes de empezar a escribir código.**
