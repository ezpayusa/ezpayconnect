# 🤖 Prompt para sesión de desarrollo — EzPayConnect Portal Proveedores

> Copia y pega esto como mensaje inicial al iniciar la sesión con Kimi Code CLI.

---

Hola, soy Kimi Code CLI. Hoy continúo el desarrollo del portal de proveedores de EzPayConnect.

## 🏗️ Stack del proyecto

- **Frontend:** React 19 + TypeScript + Vite 6 + Tailwind CSS v4 + shadcn/ui
- **Backend:** Supabase Auth + PostgreSQL
- **Routing:** React Router v7 (rutas anidadas requieren `/*` en el padre)
- **Mapas:** Leaflet + OpenStreetMap (gratuito, sin API key)
- **Edge Functions:** Supabase Functions (Deno runtime)
- **PWA:** Service Worker con workbox

## 📂 Estructura clave

```
src/proveedor/              → Todo el portal de proveedores
src/proveedor/pages/        → Páginas del portal
src/proveedor/pages/visitador/   → Páginas de visitador médico
src/proveedor/hooks/        → Hooks de Supabase
src/proveedor/layout/       → Layouts y navegación
supabase/functions/         → Edge Functions
supabase/migrations/        → Migraciones SQL
```

## ✅ Estado actual (funciona bien)

- Portal con roles: `admin`, `editor`, `visitador_medico`
- Invitación de visitadores por WhatsApp (genera token + link de registro)
- Registro de visitadores invitados (`/proveedor/registro-visitador?token=...`)
- Flujo propuesta → aprobación de visitas (admin aprueba, consume créditos del plan)
- Check-in/check-out con foto + GPS (bucket `evidencias-visitas`)
- Ruta del día con mapa Leaflet + navegación a Google Maps / Waze
- Reporte de visitas por empresa + panel EzPay de todas las visitas
- Geocodificación de direcciones (Edge Function `geocodificar`: Google primero, Nominatim fallback)
- Ubicaciones de médicos por proveedor (`ubicaciones_medico_proveedor`)
- Pool compartido de créditos de visitas por empresa

## ⚠️ Bugs conocidos / pendientes

- [ ] **Service Worker cachea versiones viejas** → requiere hard refresh (Ctrl+F5) o pestaña de incógnito para ver cambios nuevos
- [ ] `ProveedorPagosPage.tsx` está vacío (placeholder, no muestra historial real de pagos)
- [ ] `ProveedorPerfilPage.tsx` es solo lectura (no permite editar datos de empresa)
- [ ] `ProveedorDashboard.tsx` tiene placeholder de estadísticas (no muestra KPIs reales)
- [ ] **No hay sistema de notificaciones** (email / push / in-app)
- [ ] Planes de publicidad están hardcodeados en el frontend
- [ ] `PublicidadPlanesPage.tsx` no carga planes desde base de datos

## 🎯 Misión de hoy (elegir una o más)

### Opción A — Sistema de notificaciones por email (alta prioridad)
Implementar notificaciones automáticas vía Edge Function usando Resend o SendGrid:
- Admin recibe email cuando un visitador propone una visita
- Visitador recibe email cuando admin aprueba / rechaza su propuesta
- Recordatorio automático 24h antes de una visita confirmada
- Crear tabla `notificaciones` para historial in-app

### Opción B — Página de Pagos funcional (alta prioridad)
Completar `ProveedorPagosPage.tsx`:
- Mostrar historial real de pagos desde tabla `pagos_proveedor`
- Mostrar comprobantes subidos (imágenes)
- Filtros por estado: pendiente, aprobado, rechazado
- Totales por mes

### Opción C — Perfil editable (media prioridad)
Hacer `ProveedorPerfilPage.tsx` editable:
- Formulario para actualizar datos de empresa (nombre, dirección, teléfono, email, RUC)
- Subir/actualizar logo de empresa
- Actualizar datos del representante (nombre, email, teléfono)
- Guardar cambios vía Supabase (update en `empresas_proveedoras` y `cuentas_proveedor`)

### Opción D — Dashboard con estadísticas reales (media prioridad)
Reemplazar placeholder "Estadísticas próximamente" en `ProveedorDashboard.tsx`:
- Visitas este mes / semana
- Tasa de concreción (visitas completadas / totales)
- Créditos de visitador disponibles vs usados
- Productos más visitados
- Campañas publicitarias activas

### Opción E — Recordatorios de visita (media prioridad)
- Enviar email/SMS al visitador 1 hora antes de cada visita
- Enviar confirmación al médico con detalles de la visita
- Generar archivo `.ICS` (calendario) al aprobar una visita

### Opción F — Offline support / PWA robusta (baja prioridad)
- Permitir check-in con foto cuando no hay internet
- Guardar en IndexedDB y sincronizar cuando hay conexión
- Notificar al visitador cuando la sincronización fue exitosa

## 🔐 Acceso y configuración

| Recurso | Valor |
|---------|-------|
| Supabase Project | `fqnsmvkxsuujahhmpzuk` |
| Supabase URL | `https://fqnsmvkxsuujahhmpzuk.supabase.co` |
| Edge Functions deployadas | `geocodificar`, `invitar-visitador`, `validar-invitacion` |
| Google Maps API Key | Configurado en Supabase Secrets como `GOOGLE_MAPS_API_KEY` |
| Bucket de evidencias | `evidencias-visitas` (privado, acceso via RLS) |

## 📋 Reglas de código y convenciones

- **Feedback al usuario:** Usar `toast` de `sonner` para errores y éxito
- **Hooks de Supabase:** Manejar errores, mostrar toast, setear estados de loading
- **Edge Functions:** Usar `supabase-js` desde ESM (`https://esm.sh/@supabase/supabase-js@2.39.0`)
- **Migraciones SQL:** Usar `IF NOT EXISTS`, `SECURITY DEFINER` para RPCs, RLS con `auth.uid()`
- **RLS policies:** Verificar siempre `activo = true` y `rol_en_empresa` correcto
- **React Router v7:** Rutas padre con hijos anidados **deben** terminar en `/*`
- **Columnas de `cuentas_proveedor`:** `id` es FK de `auth.users(id)`, NO `usuario_id`. `activo` es boolean, NO `estado`.
- **Imágenes:** Usar `supabase.storage` para uploads, URLs públicas o signed URLs según RLS
- **Fechas:** Usar `date-fns` para manipulación de fechas, `es` locale para español

## 🚀 Flujos críticos que deben seguir funcionando

Si modificas algo relacionado con visitas, verifica que estos flujos no se rompan:
1. Visitador propone visita → trigger fuerza `estado = 'propuesta'`
2. Admin aprueba → `estado = 'confirmada'` + consume crédito
3. Visitador ve visita confirmada en "Mis Visitas"
4. Visitador hace check-in → foto + GPS en `evidencias-visitas`
5. Visitador hace check-out → visita pasa a `completada`
6. Mapa de ruta muestra paradas en orden con Leaflet

---

**Por favor indícame qué opción(es) vas a implementar hoy y hazme cualquier pregunta antes de empezar a escribir código.**
