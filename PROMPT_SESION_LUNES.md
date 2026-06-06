# Prompt de Sesión - Lunes (Retomar EzPayConnect)

## Estado Actual del Proyecto

**Fecha de corte:** Sábado 6 de junio de 2026, ~15:00 CST

---

## ✅ Lo que YA FUNCIONA (Notificaciones + Recordatorios)

### 1. Sistema de Notificaciones In-App
- **Tabla:** `notificaciones` (creada en migración 022)
- **Edge Function:** `enviar-notificacion` — crea notificaciones en la tabla
- **Usado por:** `useVisitasAgendadas.ts`, `AgendarCitaModal.tsx`, `notificaciones.ts`

### 2. Sistema de Recordatorios Automáticos
- **Tabla:** `recordatorios` (migración 022) — unifica citas médicas y visitas de proveedores
- **Edge Function:** `programar-recordatorio` — programa un recordatorio 24h antes (acepta `tipo: 'cita' | 'visita'` + `referencia_id`)
- **Edge Function:** `procesar-recordatorios` — corre cada 15 min vía cron-job.org, envía emails vía Resend + notificaciones in-app

### 3. Flujos Activos
| Acción | Qué pasa |
|--------|----------|
| Crear cita desde panel admin | Auto-programa recordatorio 24h antes |
| Paciente agenda cita vía webapp | Auto-programa recordatorio 24h antes |
| Click manual en "Recordatorio" en CitasPage | Programa recordatorio 24h antes |
| Aprobar visita de proveedor | Auto-programa recordatorio 24h antes + notificación in-app al visitador |
| Proponer/rechazar visita | Notificación in-app a admins/editores |

### 4. Configuración Deploy
- **Frontend:** Vercel (`https://ezpayconnect.vercel.app`) — build + deploy OK
- **Supabase Edge Functions:** Todas desplegadas (`programar-recordatorio`, `procesar-recordatorios`, `enviar-notificacion`, `notificar-email`)
- **Cron Job:** cron-job.org cada 15 min → `POST https://fqnsmvkxsuujahhmpzuk.supabase.co/functions/v1/procesar-recordatorios` (body: `{}`)
- **JWT deshabilitado** para `procesar-recordatorios` en `config.toml` para que cron-job.org pueda llamarla

---

## ⚠️ Pendiente Crítico

### 1. Verificar Dominio en Resend (PRODUCCIÓN)
- **Estado actual:** Los emails se envían desde `onboarding@resend.dev` (limitado a 1 destinatario de prueba por día)
- **Qué hay que hacer:** Verificar `ezpayconnect.com` en el dashboard de Resend (registrar DNS records: SPF, DKIM, DMARC)
- **Archivos a actualizar después de verificar:**
  - `supabase/functions/procesar-recordatorios/index.ts` → cambiar `from` a `EzPayConnect <no-reply@ezpayconnect.com>`
  - `supabase/functions/notificar-email/index.ts` → cambiar `from` a `EzPayConnect <no-reply@ezpayconnect.com>`
- **Impacto:** Sin esto, en producción solo se puede enviar a 1 email de prueba por día

### 2. Verificar cron-job.org en Producción
- Asegurarse de que el job en cron-job.org siga activo y no se haya "apagado" por fallos
- El toggle "Disable after failures" debe estar en naranja (enabled)

### 3. Revisar Logs de Supabase
- Ir a Supabase Dashboard → Edge Functions → Logs de `procesar-recordatorios`
- Verificar que no haya errores cuando el cron ejecute cada 15 min

---

## 🐛 Bugs Recién Arreglados (Sábado 6/jun)

1. **Edge Function `enviar-notificacion`** — Tenía `import { createClient } from "supabase"` (npm) que rompe en Deno. Se cambió a `https://esm.sh/@supabase/supabase-js@2`
2. **Edge Function `programar-recordatorio`** — Usaba queries embedidas (joins) que fallaban en Supabase. Se reescribió con queries separadas
3. **Frontend `CitasPage.tsx`** — El botón "Recordatorio" enviaba body antiguo (`cita_id`, `paciente_id`). Se actualizó al formato nuevo (`tipo: 'cita'`, `referencia_id`)
4. **Frontend `campanas.ts`** — Usaba `.group()` que no existe en Supabase JS. Se reemplazó por conteo manual
5. **Frontend `CitasPage.tsx` query a `perfiles`** — Pedía columna `nombre` (no existía), se cambió a `nombre_completo`

---

## 📁 Archivos Clave Modificados Recientemente

```
supabase/migrations/022_notificaciones_y_recordatorios.sql
supabase/functions/procesar-recordatorios/index.ts
supabase/functions/programar-recordatorio/index.ts
supabase/functions/enviar-notificacion/index.ts
supabase/functions/notificar-email/index.ts
supabase/config.toml
src/pages/CitasPage.tsx
src/hooks/useCitas.ts
src/webapp/components/AgendarCitaModal.tsx
src/proveedor/hooks/useVisitasAgendadas.ts
src/proveedor/lib/notificaciones.ts
src/lib/metricas/campanas.ts
```

---

## 🔧 Contexto Técnico Importante

- **Supabase embedded queries (joins) FALLAN** en este proyecto. Siempre usar queries separadas secuenciales
- **Edge Functions NO pueden llamarse entre sí** vía `fetch` + `serviceRoleKey` (devuelve 401). Solución: llamar directamente a la API externa (Resend) o escribir directo a DB
- **PWA con Service Worker** → Siempre usar Ctrl+F5 o incógnito para probar cambios recientes
- **Supabase free tier** → No tiene `pg_cron` ni `pg_net`. Usar cron-job.org como workaround

---

## 🎯 Próximos Pasos Sugeridos para el Lunes

1. **Verificar dominio en Resend** (crítico para producción)
2. **Probar flujo end-to-end:** Crear una cita para "mañana", verificar que `procesar-recordatorios` la procese y envíe email + notificación
3. **Revisar logs de Supabase** para confirmar que no hay errores silenciosos
4. **Verificar que cron-job.org siga funcionando**
5. **(Opcional) Mejorar UI de notificaciones** — Agregar badge/contador de notificaciones no leídas en el navbar
