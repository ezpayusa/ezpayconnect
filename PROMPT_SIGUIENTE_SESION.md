# Prompt para siguiente sesión — EzPayConnect

## 1. Contexto del proyecto

**Stack:** React 19 + TypeScript + Vite 6 + Tailwind CSS v4 + shadcn/ui
**Backend:** Supabase Auth + PostgreSQL + Edge Functions (Deno)
**Deploy:** Vercel (`https://ezpayconnect.vercel.app`)
**Supabase Project:** `fqnsmvkxsuujahhmpzuk` (West US)
**PWA:** vite-plugin-pwa con `injectManifest` (custom `src/sw.ts`)
**Push Notifications:** `webpush-webcrypto` package, VAPID keys generadas con `ApplicationServerKeys.generate()`

## 2. Estado actual de funcionalidades

| Módulo | Estado | Notas |
|--------|--------|-------|
| Registro / Auth | ✅ Funciona | Selector de país con RLS público arreglado |
| Panel Paciente (`/paciente/dashboard`) | ✅ Funciona | Agenda citas, ve recetas, exámenes, chat |
| Agendar cita (paciente) | ✅ Funciona | 2-step modal: médico/clínica → fecha/hora/motivo |
| Citas en DB | ✅ Guarda correctamente | Sin `clinica_id` por bug de PostgREST (ver bugs) |
| Push notifications | ✅ Activadas | VAPID keys compatibles con `webpush-webcrypto` |
| Service Worker | ✅ Funciona | NavigationRoute fallback a index.html arreglado |
| RLS policies | ✅ Arregladas | `get_auth_user_rol()` y `get_auth_user_pais_id()` como SECURITY DEFINER |
| Panel Clínica (`/clinica`) | ⚠️ Básico | Solo dashboard con estadísticas. **NO tiene gestión de citas** |
| Panel Médico | ❌ No existe | No hay interfaz para médicos ver sus citas pendientes |
| Notificaciones in-app | ⚠️ Edge Function existe | `enviar-notificacion` — necesita verificar que no dé 500 |
| Recordatorios 24h | ⚠️ Edge Function existe | `programar-recordatorio` — sin verificar funcionamiento real |

## 3. Bugs críticos conocidos (arreglar primero)

### Bug #1: PostgREST no reconoce `clinica_id` en tabla `citas`
- **Síntoma:** INSERT con `clinica_id` da error: `Could not find the 'clinica_id' column of 'citas' in the schema cache`
- **Importante:** La columna `clinica_id` **SÍ EXISTE** físicamente en la tabla (`INTEGER REFERENCES clinicas(id)` desde migración inicial).
- **Workaround actual:** El INSERT en `AgendarCitaModal.tsx` omite `clinica_id` del payload. La cita se guarda sin asociación a clínica.
- **Lo intentado:** Restart del proyecto Supabase desde Dashboard → **NO resolvió** el problema.
- **Solución propuesta:** Crear una función SQL `crear_cita()` + llamarla vía `supabase.rpc()` para saltar PostgREST por completo en el INSERT.

### Bug #2: `enviar-notificacion` y `enviar-push` dieron 500 al agendar cita
- **Síntoma:** En la consola del navegador aparece `500 Internal Server Error` al invocar estas Edge Functions desde `AgendarCitaModal.tsx`.
- **Sin logs detallados disponibles** (CLI de Supabase no tiene acceso a logs remotos).
- **Revisar:** Verificar en Supabase Dashboard → Edge Functions → Logs qué error específico arrojan.

## 4. Features faltantes prioritarias

### Feature A: Panel de Médico / Clínica para gestionar citas
El médico y la clínica **no tienen forma de ver las citas solicitadas**.

**Lo que debe incluir:**
- 📋 Listado de citas con estado `pendiente` / `solicitada` / `confirmada`
- ✅ Botón para **confirmar** cita (cambia estado a `confirmada`)
- ❌ Botón para **rechazar** cita (cambia estado a `cancelada`)
- 📅 Vista de calendario con citas agendadas
- 🔔 Al confirmar/rechazar, enviar notificación in-app + push al paciente
- 📍 Mostrar nombre del paciente, fecha, hora, motivo, notas

**Rutas sugeridas:**
- `/medico/citas` — Panel del médico
- `/clinica/citas` — Panel de la clínica (o reutilizar el mismo componente con rol check)

### Feature B: Mejorar UX del flujo "Agendar cita" (propuesta del usuario)

**Problema actual:** Se muestra lista plana de todos los médicos y clínicas. No escala.

**Mejoras propuestas:**

1. **Autocomplete / búsqueda inteligente**
   - Reemplazar lista plana por un input de búsqueda con debounce
   - Filtrar por `nombre_completo`, `especialidad`, nombre de clínica
   - Resultados limitados a 5-7 con highlight
   - "Sin preferencia" como opción default seleccionada

2. **Filtrar clínicas por médico seleccionado**
   - Al seleccionar un médico, mostrar **solo las clínicas donde atiende** (usar tabla `medico_clinicas`)
   - Si el médico atiende en una sola clínica, preseleccionarla automáticamente

3. **Médico primario + Clínica primaria en perfil del paciente**
   - Agregar campos `medico_primario_id` y `clinica_primaria_id` a tabla `pacientes`
   - En el modal de agendar, pre-cargar esos valores por defecto
   - Checkbox "Recordar como mi preferencia" si el usuario cambia la selección

4. **Búsqueda por especialidad / sinónimos básicos**
   - Buscar "corazon" → encuentra "Cardiología"
   - Buscar "niños" → encuentra "Pediatría"
   - Implementar con `ilike` + normalización (quitar tildes, minúsculas) — suficiente para 100-200 registros

5. **Opción de agendar en laboratorio clínico (futuro)**
   - Extender modelo: `tipo: 'consulta' | 'laboratorio'`
   - Nueva tabla `laboratorios` o extender `clinicas`
   - Flujo diferente: puede no requerir médico, solo orden de examen
   - **Prioridad baja:** dejar para fase 2 después de validar consultas médicas

6. **Flujo inteligente de asignación**
   - Si el paciente tiene médico primario y clínica primaria:
     - Preseleccionar ambos
     - Si la cita es por referencia de especialidad, permitir cambiar médico/clínica
   - Si no tiene médico primario:
     - Mostrar búsqueda completa con "Sin preferencia" como default

## 5. Tareas concretas para la siguiente sesión

**Prioridad Alta:**
- [ ] Arreglar Bug #1: Crear función SQL `crear_cita()` + usar `supabase.rpc()` para insertar citas con `clinica_id`
- [ ] Arreglar Bug #2: Verificar logs de `enviar-notificacion` y `enviar-push` en Supabase Dashboard, corregir errores
- [ ] Feature A: Crear panel `/medico/citas` o `/clinica/citas` para ver y gestionar citas pendientes
- [ ] Feature A: Implementar botones Confirmar/Rechazar con cambio de estado en DB
- [ ] Feature A: Al confirmar/rechazar, enviar notificación in-app + push al paciente

**Prioridad Media:**
- [ ] Feature B.1: Reemplazar lista plana de médicos por autocomplete con búsqueda
- [ ] Feature B.2: Filtrar clínicas según médico seleccionado (`medico_clinicas`)
- [ ] Feature B.3: Agregar `medico_primario_id` y `clinica_primaria_id` a `pacientes` + preselección

**Prioridad Baja (futuro):**
- [ ] Feature B.5: Citas en laboratorio clínico
- [ ] Bundle splitting: Reducir main chunk (~2.26 MB)

## 6. Archivos clave a conocer

- `src/webapp/components/AgendarCitaModal.tsx` — Modal de agendar cita (2 pasos)
- `src/webapp/hooks/useWebAppCitas.ts` — Hook que carga citas del paciente
- `src/lib/push-config.ts` — VAPID public key
- `src/webapp/hooks/usePushNotifications.ts` — Lógica de suscripción push
- `supabase/functions/enviar-push/index.ts` — Edge Function de push
- `supabase/functions/enviar-notificacion/index.ts` — Edge Function de notificaciones in-app
- `supabase/functions/programar-recordatorio/index.ts` — Edge Function de recordatorios
- `supabase/migrations/001_inicial.sql` — Schema base incluyendo `citas` con `clinica_id`
- `src/sw.ts` — Service Worker personalizado

## 7. Consideraciones técnicas

- **PostgREST schema cache:** Si una columna existe en PostgreSQL pero PostgREST da "schema cache", usar `.rpc('nombre_funcion')` o Edge Functions para saltar el cache.
- **RLS:** Las Edge Functions usan `SUPABASE_SERVICE_ROLE_KEY` y deben saltarse RLS. Si hay errores 500, verificar que la función esté leyendo el secret correctamente.
- **VAPID keys:** Usar keys generadas por `webpush-webcrypto.ApplicationServerKeys.generate()` (formato base64url). No usar keys de `web-push` npm ya que pueden tener formato incompatible.
- **PWA:** Siempre testear SW con Ctrl+F5 o incognito. El fallback de navegación usa `NavigationRoute` a `index.html`.
