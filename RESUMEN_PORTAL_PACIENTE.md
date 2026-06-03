# 📋 Resumen — Portal del Paciente EzPayConnect

> Última actualización: 2026-06-03
> Sesión: PASO 1 al PASO 6 completados

---

## 📁 Archivos creados/modificados

| Archivo | Descripción |
|---------|-------------|
| `src/webapp/hooks/useWebAppAuth.ts` | Auth del portal (login, register, logout, perfil paciente) |
| `src/webapp/hooks/useWebAppCitas.ts` | Fetch citas del paciente desde Supabase |
| `src/webapp/hooks/useWebAppRecetas.ts` | Fetch recetas + items del paciente |
| `src/webapp/hooks/useWebAppExamenes.ts` | Fetch exámenes del paciente |
| `src/webapp/hooks/useWebAppChat.ts` | Chat en tiempo real (enviar, recibir, suscripción Supabase) |
| `src/webapp/hooks/useWebAppNotificaciones.ts` | Notificaciones con dropdown y realtime |
| `src/webapp/layout/WebAppPrivateRoute.tsx` | Protege rutas del portal (solo pacientes válidos) |
| `src/webapp/layout/WebAppLayout.tsx` | Layout con header y campana de notificaciones |
| `src/webapp/layout/WebAppSidebar.tsx` | Sidebar de navegación |
| `src/webapp/components/NotificacionesDropdown.tsx` | Dropdown de notificaciones con iconos |
| `src/webapp/pages/WebAppDashboard.tsx` | Dashboard con contadores dinámicos |
| `src/webapp/pages/WebAppCitas.tsx` | Lista de citas con tabs (próximas/pasadas/canceladas) |
| `src/webapp/pages/WebAppRecetas.tsx` | Lista de recetas expandibles con medicamentos |
| `src/webapp/pages/WebAppExamenes.tsx` | Lista de exámenes con resultados |
| `src/webapp/pages/WebAppChat.tsx` | UI de chat con input y burbujas |
| `src/webapp/pages/WebAppPerfil.tsx` | Perfil editable (nombre, teléfono, alergias, emergencia, etc.) |
| `src/webapp/pages/WebAppLoginPage.tsx` | Login del paciente |
| `src/webapp/pages/WebAppRegistroPage.tsx` | Registro del paciente |
| `src/webapp/types/webapp.types.ts` | Tipos del portal (PacientePerfil, CitaPaciente, RecetaPaciente, etc.) |
| `src/App.tsx` | Rutas del portal agregadas al enrutador principal |
| `src/index.css` | Clases utilitarias agregadas para el portal |

---

## ✅ Funcionalidades listas

### 1. Auth de pacientes
- Registro (`/paciente/registro`) con creación automática de perfil en tabla `pacientes`
- Login (`/paciente/login`)
- Logout
- Detecta si el usuario logueado es paciente o médico
- **Config requerida en Supabase:** Confirm email = DISABLED, Email provider = ENABLED

### 2. Protección de rutas
- `WebAppPrivateRoute` verifica que el usuario sea un paciente válido en tabla `pacientes`
- Médicos logueados ven "Acceso restringido" con botón de logout
- Usuarios sin sesión son redirigidos a `/paciente/login`

### 3. Dashboard
- Muestra contadores reales: próximas citas, recetas activas, exámenes pendientes
- Tarjeta de próxima cita (fecha, hora, médico, motivo)
- Quick actions (agendar cita)

### 4. Citas
- Tabs: Próximas, Pasadas, Canceladas
- Compatible con estado `pendiente` del panel médico (además de agendada/confirmada/etc.)
- Muestra médico asignado (buscado desde `perfiles` por separado)

### 5. Recetas
- Lista expandible con items de medicamentos
- Dosis, frecuencia, duración, cantidad, instrucciones

### 6. Exámenes
- Lista con tipo, fecha, estado, resultados, archivo adjunto

### 7. Chat en tiempo real
- Envía mensajes (funciona sin médico asignado)
- Suscripción Supabase Realtime: mensajes aparecen automáticamente sin F5
- Burbujas de chat con hora y estado (Enviado/Leído)

### 8. Notificaciones
- Dropdown al hacer click en la campana (header)
- Badge con contador de no leídas
- Iconos por tipo: cita, receta, examen, mensaje, general
- Marcar individualmente como leída al hacer click
- Botón "Marcar todas como leídas"
- Realtime: nuevas notificaciones aparecen automáticamente

### 9. Perfil editable
- Botón "Editar" activa modo edición
- Campos: nombre, apellido, teléfono, fecha nacimiento, género, dirección, alergias, notas médicas, contacto de emergencia
- Botón Guardar actualiza en Supabase y recarga la página
- **Fix importante:** Componente `CampoPerfil` está definido FUERA de `WebAppPerfil` para evitar perder foco al escribir

---

## ⚠️ Migraciones SQL ejecutadas en Supabase

Ejecutar en Supabase SQL Editor SI NO están aplicadas:

```sql
-- 004: Tablas del portal (ya debería estar ejecutada)
-- 005: RLS paciente + tabla examenes (ya debería estar ejecutada)
-- 006: medico_id nullable en pacientes (ya debería estar ejecutada)
-- 007: medico_id nullable en chat_mensajes (ya debería estar ejecutada)
-- 008: Enable Realtime en chat_mensajes (ya debería estar ejecutada)
```

**Verificar que chat_mensajes tenga Realtime:**
```sql
-- Verificar que la tabla está en la publicación
SELECT * FROM pg_publication_tables WHERE pubname = 'supabase_realtime';
```

---

## ❌ Lo que falta por hacer

| # | Funcionalidad | Prioridad |
|---|--------------|-----------|
| 1 | **Historial médico** | Alta — Página `WebAppHistorial.tsx` está vacía. Falta combinar citas + recetas + exámenes en una línea de tiempo |
| 2 | **Notificaciones push del navegador** | Media — Ahora solo hay notificaciones in-app. Faltaría service worker + Push API para notificaciones nativas del navegador |
| 3 | **Agendar citas desde el portal** | Baja — El botón "Agendar cita" no tiene acción. Necesitaría un formulario/modal para crear citas |
| 4 | **Chat con médico real** | Baja — El chat funciona sin médico asignado porque los datos de demo no tienen médicos reales en `perfiles`. Para producción se necesita vincular médicos reales |

---

## 🔧 Notas técnicas importantes

### Supabase Auth Settings
- **Sign In / Providers → Email:** ENABLED
- **Confirm email:** DISABLED (para pruebas)
- **Allow new users to sign up:** ENABLED

### Paciente de prueba
- **Email:** `koka@prueba.com`
- **Contraseña:** `123456`
- **Paciente ID en BD:** 15
- **auth_user_id:** vinculado correctamente

### Problemas resueltos (para recordar)
1. **RLS:** Pacientes necesitan políticas RLS para leer sus propias citas/recetas
2. **medico_id:** Se hizo nullable en `pacientes` y `chat_mensajes` para permitir registros sin médico
3. **Realtime:** Se requiere `REPLICA IDENTITY FULL` + tabla en publicación `supabase_realtime`
4. **Schema cache error:** Los hooks de citas/recetas obtienen el nombre del médico en una query separada (no con join de Supabase)
5. **Pendiente en citas:** El panel médico crea citas con estado `pendiente`, no en el ENUM original. Se agregó soporte para este estado.

### Stack
- React 19 + TypeScript + Vite 6 + Tailwind CSS v4
- shadcn/ui (Button, Input, Card, Badge, Label)
- Supabase (auth + BD + realtime)
- Lucide React (iconos)
- Sonner (toasts)

---

## 🚀 Para retomar mañana

1. Clonar/pull del repo `ezpayusa/ezpayconnect` (rama `main`)
2. `npm install` (si es nuevo entorno)
3. `npm run dev` (servidor en `localhost:5173`)
4. Verificar que las migraciones SQL estén aplicadas en Supabase
5. Login con `koka@prueba.com` / `123456`
6. Continuar con **Historial médico** (PASO 7) o terminar aquí

---

## 📞 Commits en main (más recientes primero)

- `894f011` — PASO 6 fix: Componente CampoPerfil fuera de WebAppPerfil
- `ecf269f` — PASO 6: Perfil del paciente editable
- `b8f20c7` — PASO 5 fix: Elimina canal realtime anterior
- `8d47dbe` — PASO 5: Sistema de notificaciones con dropdown
- `f872ded` — PASO 4 fix: Mejora suscripción Realtime chat
- `8b30e70` — PASO 4 fix: Chat funciona sin medico asignado
- `ae2e515` — PASO 4 fix: Verifica que medico exista en perfiles
- `aad1617` — PASO 4 fix: Chat permite mensajes sin medico_id
- `9a9a31c` — PASO 4: Chat en tiempo real
- `a0ead28` — PASO 3 fix: Agrega estado pendiente a citas
- `977334d` — PASO 3 fix: Hooks citas/recetas obtienen medico por separado
- `15d937e` — PASO 3: Dashboard conectado a Supabase + hooks
- `cc7ab7e` — PASO 2 fix: Solo pacientes pueden entrar al portal
- `12fa6d5` — PASO 2 fix: Boton cerrar sesion en acceso restringido
- `ceb48ca` — PASO 2 fix: Solo pacientes pueden entrar al portal
- `ccd6893` — Protección de rutas del portal del paciente
- `fdd0320` — Estructura base portal del paciente
