# 📋 PROMPT PARA SIGUIENTE SESIÓN — EzPayConnect

**Objetivo:** Resolver todos los bugs pendientes para iniciar operaciones de citas en producción.

---

## ▶️ RESUME AQUÍ (2026-07-16) — Circuito laboratorio

- **Bug storage (lab no podía subir archivo): CERRADO en prod.** Read-back de `storage.objects`; fix = rama
  "dueño del prefijo" en `resultados_scoped_select`. Archivo `supabase/fixes/fix_resultados_select_readback.sql`.
- **Gate "liberado al paciente": CONSTRUIDO + VALIDADO EN LOCAL; DB viva en prod; frontend PENDIENTE DE DEPLOY**
  (va con la consolidación Vercel). Columnas en `examenes` + 2 policies de enforcement + 3 RPCs
  (`liberar_examen_al_paciente`, `liberar_orden_al_paciente`, `paciente_examenes`) + split de
  `notificar_resultado_examen`. Frontend: `PacienteDetallePage.tsx`, `useWebAppExamenes.ts`,
  `WebAppExamenes.tsx`, `webapp.types.ts`. Typecheck 88 (baseline). Detalle completo en `DISENO-FASE4-LAB.md`.
- **Frente 2: en diagnóstico** (recon Codex hecho, 6 hallazgos en `DISENO-FASE4-LAB.md` / `ESTADO_PROYECTO`).

**Próximos fixes, en orden:**
1. **(3) Fechas** — off-by-one por parseo/seteo en UTC; usar `src/lib/fecha.ts` (`parseFechaLocal`/`hoyISO`).
2. **(5) Fila examen `id=1`** — `archivo_url` público en bucket privado; normalizar a path con `-f`.
3. **(2) Rename cosmético** — `ordenId` es en realidad `examenes.id`; corregir toast/nombres.
4. **Consolidación Vercel** — deployar todo el frontend acumulado (incluye el gate de liberación).

> Deuda vigente: `schema_migrations` en 047 → **NUNCA `db push`**; aplicar con `-f`; **NUNCA `functions deploy` sin nombre**.

---

## 🔴 CRÍTICO — Flujo de Citas Clínica NO Funciona

### Problema: Citas aparecen como "Agendada" en vez de "Solicitada" para aprobación
**Reportado por usuario:** "citas no pasa en el panel de clinica citas para ser aprobada, aparece asignada"

- Cuando paciente agenda cita SIN médico → debería crear `estado = 'solicitada'`
- En panel de clínica, la cita debería aparecer como **"Solicitada"** con opción de **asignar médico + confirmar**
- Actualmente aparece como **"Agendada"** y no permite el flujo de aprobación correcto

**Archivos a revisar:**
- `src/webapp/components/AgendarCitaModal.tsx` — lógica de `estado` al crear cita
- `src/clinica/hooks/useClinicaCitas.ts` — `asignarMedico()`, `confirmarCita()`, `rechazarCita()`
- `src/clinica/pages/ClinicaCitasPage.tsx` — UI de citas, botones de acción por estado
- `src/medico/hooks/useMedicoCitas.ts` — flujo del médico para confirmar/rechazar
- Supabase RPC `obtener_citas_clinica` — verificar que retorna citas con estado correcto
- Supabase RPC `crear_cita` — verificar que el estado se guarda correctamente

**Escenarios a testear:**
1. Paciente agenda cita SIN médico → `estado = 'solicitada'`
2. Clínica ve cita "Solicitada" → puede asignar médico → cambia a "Agendada"
3. Clínica confirma cita "Agendada" → cambia a "Confirmada"
4. Clínica rechaza cita → cambia a "Cancelada"
5. Paciente agenda cita CON médico → `estado = 'agendada'` directamente
6. Notificaciones push llegan en cada cambio de estado

---

## 🔴 CRÍTICO — Vercel Sirve Bundle Viejo (Service Worker Cache)

### Problema: El navegador carga `index-BdDRygo3.js` en vez del bundle más reciente

- Vercel deploya correctamente pero el SW precachea bundles antiguos
- Los usuarios ven código viejo incluso después de deploy exitoso
- Causa errores de íconos (`MapPin is not defined`, etc.) porque el bundle viejo no tiene los fixes

**Archivos a revisar:**
- `src/sw.ts` — Service Worker, `skipWaiting()`, limpieza de caches
- `vite.config.ts` — Configuración de `vite-plugin-pwa`
- `src/main.tsx` — Posible listener de mensajes del SW para recarga forzada

**Soluciones posibles:**
1. Desactivar temporalmente el precaching de workbox (modo desarrollo)
2. Agregar un hash de versión en `index.html` para forzar cache-busting
3. Implementar recarga automática cuando el SW detecta nueva versión
4. O: Eliminar PWA temporalmente hasta que el flujo de citas esté estable

**Verificación:**
- Abrir DevTools → Network → verificar hash del bundle `index-XXXXX.js`
- Comparar con hash del build local (`npm run build` → `dist/assets/`)

---

## 🟠 ALTO — Íconos de lucide-react Fallan en Producción

### Patrón identificado:
| Ícono | Local | Producción (Vercel) |
|-------|-------|---------------------|
| `Building2` | ✅ | ❌ `not defined` |
| `Building` | ✅ | ❌ `not defined` |
| `Home` | ✅ | ❌ `not defined` |
| `MapPin` | ✅ | ❌ `not defined` (en bundle viejo) |

**Hipótesis:** El tree-shaking de Vite/Rollup elimina íconos que no detecta como usados, o la versión de lucide-react tiene problemas con ciertos íconos en build de producción.

**Investigar:**
- Probar importar íconos individualmente: `import { MapPin } from 'lucide-react/dist/esm/icons/map-pin'`
- O usar `import MapPin from 'lucide-react/dist/esm/icons/map-pin'`
- O considerar cambiar a `@heroicons/react` o `react-icons` si el problema persiste
- Verificar configuración de `treeshake` en `vite.config.ts`

---

## 🟡 MEDIO — Notificaciones Push No Testeadas en Producción

### Estado actual:
- ✅ Tabla `push_subscriptions` creada con índice único en `endpoint`
- ✅ Edge Function `enviar-push` implementada con `webpush-webcrypto`
- ✅ VAPID keys configuradas en Supabase secrets
- ✅ Hook `usePushNotifications.ts` con auto-suscripción
- ✅ Service Worker con handler de push events
- ❌ **NO TESTEADO** end-to-end en producción

**Tareas pendientes:**
1. Verificar que `enviar-push` edge function se deployó correctamente (`supabase functions list`)
2. Verificar VAPID keys en Supabase (`supabase secrets list`)
3. Testear: paciente agenda cita → llega push
4. Testear: clínica confirma cita → paciente recibe push
5. Testear: clínica cancela cita → paciente recibe push
6. Verificar que la suscripción se guarda correctamente en `push_subscriptions`

**Debug:**
```javascript
// En DevTools Console del paciente
navigator.serviceWorker.ready.then(reg => {
  reg.pushManager.getSubscription().then(sub => {
    console.log('Subscription:', sub);
  });
});
```

---

## 🟡 MEDIO — Estados de Citas Inconsistentes en TypeScript vs PostgreSQL

### Ya parcialmente corregido pero verificar:
- `src/types/index.ts` — tipo `Cita` ahora tiene estados correctos
- `src/types/types-con-factura.ts` — corregido
- `src/types/types-index.ts` — corregido
- `src/webapp/types/webapp.types.ts` — corregido
- `src/pages/CitasPage.tsx` — corregido `'pendiente'` → `'agendada'`

**Verificar que NO quede `'pendiente'` en ningún lugar para citas:**
```bash
grep -rn "estado.*pendiente\|'pendiente'" src/ --include="*.ts" --include="*.tsx" | grep -v "notif\|WhatsApp\|PlanStatus\|admin-ezpay\|Factura\|Receta\|Examen\|Proveedor\|Visita\|Pago"
```

**Verificar consistencia con ENUM PostgreSQL:**
```sql
SELECT enumlabel FROM pg_enum WHERE enumtypid = 'cita_estado'::regtype;
-- Esperado: agendada, confirmada, en_curso, completada, cancelada, no_show, solicitada
```

---

## 🟢 BAJO — Testing End-to-End Completo

### Documento ya creado: `TESTING_CITAS.md`

**Flujos a testear manualmente antes de iniciar operaciones:**
1. ✅ Paciente agenda cita CON doctor → `estado = 'agendada'`
2. ❓ Paciente agenda cita SIN doctor → `estado = 'solicitada'` (VERIFICAR)
3. ❓ Clínica ve cita "Solicitada" y asigna médico (VERIFICAR)
4. ❓ Clínica confirma cita → notificación push al paciente (VERIFICAR)
5. ❓ Clínica cancela cita → notificación push al paciente (VERIFICAR)
6. ✅ Multi-clínica: selector funciona
7. ❓ Service Worker actualiza correctamente (VERIFICAR)
8. ❓ Push notifications funcionan en producción (VERIFICAR)

---

## 🔧 TAREAS TÉCNICAS ADICIONALES

### 1. Verificar deploy de Edge Functions
```bash
supabase functions list
# Deben estar las 30 funciones incluyendo:
# - enviar-push
# - enviar-notificacion
# - crear_cita (RPC)
# - obtener_citas_clinica (RPC)
# - obtener_clinica_usuario (RPC)
```

### 2. Verificar migraciones aplicadas en producción
```sql
-- En Supabase SQL Editor
SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 10;
-- Verificar que 039_fix_clinica_id_uuid.sql está aplicada
```

### 3. Verificar datos de prueba
- ¿Existen médicos vinculados a clínicas en `medico_clinicas`?
- ¿Los médicos de `perfiles` están sincronizados con `medicos`?
- ¿El usuario `doctor@prueba.com` tiene acceso a clínicas en `obtener_clinica_usuario`?

### 4. Limpieza de builds fallidos en Vercel
- Cancelar builds en cola si los hay
- Verificar que el deploy más reciente es el que está activo

---

## 📊 ESTADO ACTUAL DEL PROYECTO

### ✅ Funciona:
- Paciente puede agendar cita desde portal webapp
- Clínica puede cambiar entre múltiples clínicas
- Multi-clínica: selector de clínica funciona
- Edge Functions deployadas (30 funciones)
- Schema de BD corregido (UUID para clinica_id)
- Auto-suscripción push notifications implementada

### ❌ No funciona / Pendiente:
- Flujo de citas clínica (asignar médico + confirmar)
- Service Worker cachea bundles viejos
- Íconos de lucide-react en bundle de producción
- Notificaciones push no testeadas end-to-end
- Build de Vercel puede servir código stale

---

## 🎯 PRIORIDADES PARA MAÑANA

1. **🔴 CRÍTICO:** Arreglar flujo de citas en panel de clínica (asignar médico + confirmar)
2. **🔴 CRÍTICO:** Resolver caching del Service Worker o desactivar PWA temporalmente
3. **🟠 ALTO:** Testear notificaciones push end-to-end
4. **🟡 MEDIO:** Resolver problema de íconos de lucide-react en producción
5. **🟢 BAJO:** Testing manual completo del flujo de citas

---

## 📝 NOTAS TÉCNICAS

- **Stack:** React 19 + TypeScript + Vite 6 + Tailwind CSS v4 + shadcn/ui + lucide-react 0.507.0
- **Backend:** Supabase Auth + PostgreSQL + Edge Functions (Deno)
- **Deploy:** Vercel Pro (`https://ezpayconnect.vercel.app`)
- **PWA:** vite-plugin-pwa con custom `src/sw.ts`
- **Push:** `webpush-webcrypto` con VAPID keys
- **Secrets:** `SB_URL`, `SB_SERVICE_ROLE_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`

- **Build local exitoso:** Sí (commit `95e445e`)
- **Build en Vercel:** Verificar estado en dashboard
- **Bundle hash local:** `index-MZQ8pohj.js`
- **Bundle hash en producción:** `index-BdDRygo3.js` (¡DIFERENTE!)
