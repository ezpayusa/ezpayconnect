# 📊 Estado del Proyecto EzPayConnect

> Fecha: 2026-06-07
> Última sesión: Fase 8 completada (planes unificados por país + notificaciones proveedor + fallback email)

---

## 🏗️ Visión General

EzPayConnect es una **plataforma SaaS médica multitenant por país** con 3 portales principales:

1. **Panel Médico Profesional** — Consultas SOAP, recetas, signos vitales, citas, IA, facturas
2. **Portal de Proveedores** — Visitadores médicos, campañas publicitarias, check-in/check-out GPS
3. **Portal del Paciente (WebApp)** — Citas, recetas, exámenes, chat, historial médico, perfil

**Stack:** React 19 + TypeScript + Vite 6 + Tailwind CSS v4 + shadcn/ui + Supabase (PostgreSQL + Edge Functions + Auth) + Vercel

---

## 2026-07-17 — Ramas ordenadas + foto-médico + foto-calendario + planes lab/farmacia (TODO en prod)
- O1 flag: 0. GitHub recuperado de la caída del 16-17 jul (All Systems Operational).
- RAMAS: PR #4 fix/root-redirect-por-rol (root redirect por rol + AuthContext maybeSingle) mergeado.
  feat/foto-medico, feat/foto-medico-calendario, feat/planes-lab-farmacia creadas → mergeadas a main. Sin ramas pendientes.
  Convención confirmada: supabase/fixes/*.sql se commitean con `git add -f` (carpeta fixes/ gitignoreada a propósito).
- FOTO-MÉDICO (completo): backend (bucket fotos-medicos + 4 policies + RPC guardar_foto_medico escribe medicos.foto_url
  Y perfiles.avatar_url) + /medico/perfil (MedicoPerfilPage) + calendario clínica (listar_medicos_clinica ahora
  devuelve foto_url=COALESCE(medicos.foto_url,perfiles.avatar_url); DROP+CREATE por cambio de RETURNS TABLE).
  Cara-al-paciente (agendar/chat) ya la mostraba, sin tocar. Archivos: foto_medico_01.sql, foto_calendario_clinica_01.sql.
- PLANES LAB/FARMACIA (completo, Bloques 1-4): B1 DB (capacidades + otorgar_capacidad_empresa + backfill grandfathered
  lab 1/farmacia 3 hasta=NULL, verificado) → B2 checkout (PlanesLabPage cablea /proveedor/checkout tipo=plan_laboratorio;
  nueva PlanesFarmaciaPage pública /planes-farmacia tipo=plan_farmacia; lab/farmacia reusan cuentas_proveedor) →
  B3 verify (PagosProveedoresPage: al verificar plan_laboratorio/plan_farmacia → otorgar_capacidad_empresa con
  hasta=hoy+duracion_dias; fail-closed) → B4 gate (LaboratorioLayout/FarmaciaLayout leen mis_capacidades → "Plan inactivo"
  sin capacidad; UI-only, gate server-side post-piloto). mis_capacidades: (hasta IS NULL OR hasta>now()) confirmado.
  Periodicidad anual real = diferida (checkout no manda mensual/anual; usa duracion_dias como visitador).
- tsc baseline BAJÓ 88→82 (fix PlanConfiguracion.plan_base_id, drift real que contaba 7 errores).
- Pendientes vivos: (1) email facturas FacturasPage:140 alert simulado; (2) limpieza ~38 filas QA; (3) chicos:
  PlanesVisitadorPage pública alert gemelo [D] + foto en Personal de clínica; (4) diferidos post-piloto.

## 2026-07-16 — Circuito laboratorio: storage cerrado + gate liberación al paciente
- O1 flag: 0 (15-16 jul).
- BUG STORAGE (lab no podía subir archivo): CERRADO en prod. Causa = read-back de storage.objects: la policy
  SELECT resultados_scoped_select exigía que un examen ya referenciara el objeto, imposible al momento del upload.
  Fix: ALTER POLICY + rama "dueño del prefijo" split_part(name,'/',1)=mi_empresa_proveedor().
  Archivo: supabase/fixes/fix_resultados_select_readback.sql. Validado end-to-end.
- GATE "LIBERADO AL PACIENTE": construido + validado en local; DB viva en prod; FRONTEND DEPLOYADO en prod (merge d0e64a3).
  examenes +liberado_al_paciente/fecha_liberacion/liberado_por; policies de
  enforcement (storage rama paciente AND liberado; examenes paciente AND (liberado OR estado<>completado));
  RPCs liberar_examen_al_paciente / liberar_orden_al_paciente / paciente_examenes (enmascara "en revisión");
  split de notificar_resultado_examen (al subir avisa solo al médico). Archivos: supabase/fixes/fase4_01_*.sql,
  fase4_02_*.sql. Frontend: PacienteDetallePage.tsx, useWebAppExamenes.ts, WebAppExamenes.tsx, webapp.types.ts.
  Typecheck 88 (baseline), sin regresión.
- FRENTE 2 (hallazgos de la corrida) — en diagnóstico (recon Codex hecho):
  (1) flujo de estados permite saltar en_proceso (recibida→completado); estado 'revision' sin uso — a definir.
  (2) por-examen vs por-orden: solo cosmético (param 'ordenId' es examenes.id; toast "Orden actualizada" engañoso).
  (3) BUG FECHAS confirmado: WebAppExamenes usa new Date(iso) (UTC→día -1) y useLaboratorio setea fecha_resultado
      con toISOString().slice(0,10) (UTC). Ya existe src/lib/fecha.ts (parseFechaLocal/hoyISO) que lo evita → fix = usarlo.
  (4) archivo_url pisado con NULL: FALSO POSITIVO, spread condicional lo evita. Sin acción.
  (5) examen id=1 tiene archivo_url público en bucket privado (data vieja, 1 fila) → normalizar a path con -f.
  (6) estado='completado' sin archivo: texto obligatorio, archivo opcional → decisión de producto pendiente.
- Deuda: schema_migrations en 047 → NUNCA db push; aplicar con -f; NUNCA functions deploy sin nombre.

### FRENTE 3 — Personal y Roles del lab: CERRADO + DEPLOYADO (merge e72d976)
- Reuso del modelo data-driven de farmacia (cero backend nuevo salvo seed).
- Seed: 3 roles (admin niv100 es_admin / tecnico niv40 / recepcion niv40) + 9 filas de permisos en
  roles_empresa_catalogo y permisos_empresa_rol para laboratorio_clinico. Acciones: usuarios_roles, config_empresa,
  catalogo_examenes_editar, resultados_cargar, walkin_registrar, afiliaciones_gestionar.
  Archivo: supabase/fixes/fase3_01_seed_roles_laboratorio.sql (ya vivo en prod).
- Frontend: useLaboratorioPermisos (copia del hook data-driven de farmacia), LabPersonalPage (espejo de
  FarmaciaPersonalPage, sin sucursales, con toggle activar/desactivar), ruta /laboratorio/personal, ítem en sidebar.
- Gates: sidebar por accion; internos en LabOrdenes (resultados_cargar), LabCatalogo (catalogo_examenes_editar),
  LabWalkIn (walkin_registrar, gate de pagina), LabAfiliaciones (afiliaciones_gestionar, gate de pagina),
  LabPerfil (config_empresa). Alta vía edge invitar-staff-proveedor (ya deployado, tipo-agnostico). typecheck 88.
- Matriz: Admin=todo; Tecnico=resultados_cargar; Recepcion=walkin_registrar+afiliaciones_gestionar.

### FRENTE 2 (hallazgos de la corrida)
- Cerrados y en prod: (2) rename ordenId->examenId, (3) fechas locales (src/lib/fecha.ts), (5) normalizar archivo_url examen 1.
- (4) archivo_url pisado con NULL = falso positivo, sin accion.
- PENDIENTES DE DECISION DE PRODUCTO: (1) el flujo de estados permite saltar en_proceso (recibida->completado) y el
  estado 'revision' del mapa esta sin uso; (6) 'completado' sin archivo (hoy: texto obligatorio, archivo opcional -> valido).

### DEUDA NUEVA detectada hoy (para agendar)
### FRENTE PENDIENTE — Reset / Set-password (gap TRANSVERSAL + seguridad)
Recon (solo lectura) confirmó que NINGUN modulo (medico, paciente, proveedor, farmacia, laboratorio, repartidor,
clinica, admin) tiene: (a) link "olvidaste tu contrasena?"/resetPasswordForEmail, (b) pagina/handler que reciba el
recovery y setee la clave (no updateUser({password}), no evento PASSWORD_RECOVERY, no ruta reset), (c) consumo de
user_metadata.must_change_password. El link de recovery cae en / -> /dashboard.
SEGURIDAD: el edge invitar-staff-proveedor crea staff con password temporal en texto plano de larga duracion +
flag must_change_password que HOY NADIE lee (la propia edge lo documenta como "DEUDA INTERINA Ola-4"). Prioridad antes del go-live.
Alcance (una sola pagina resuelve los 8 modulos):
  1. Ruta compartida /set-password (o /restablecer): detecta sesion de recovery o must_change_password -> form -> supabase.auth.updateUser({password}).
  2. Link "Olvidaste tu contrasena?" en cada login -> resetPasswordForEmail(email, {redirectTo:<set-password>}).
  3. Guard global: al loguear, si user_metadata.must_change_password -> forzar /set-password.
  4. Edge invitar-staff-proveedor: reemplazar temp-password por generateLink(type:'recovery', redirectTo=<set-password>) (cierre Ola-4 que el propio comentario propone).
  5. Config Supabase: agregar la ruta a additional_redirect_urls (allowlist) + confirmar Site URL de prod.
- Una cuenta puede ser medico (perfiles) y staff de proveedor (cuentas_proveedor) a la vez (caso OG) — comportamiento ok, tenerlo presente.

---

## ✅ LO QUE YA ESTÁ IMPLEMENTADO

### 1. Panel Médico Profesional (`src/pages/`)

| Funcionalidad | Estado | Notas |
|--------------|--------|-------|
| Consulta unificada `/consulta/:citaId` | ✅ Completo | Layout 3 columnas: SOAP + signos vitales + acciones |
| Nota SOAP (5 pestañas) | ✅ Completo | Motivo, Subjetivo, Objetivo, Análisis, Plan |
| Dictado por voz | ✅ Completo | MediaRecorder → OpenAI Whisper Edge Function |
| Signos vitales + IMC automático | ✅ Completo | Triggers SQL calculan IMC |
| Biblioteca Médica (PubMed + Wikipedia) | ✅ Completo | Edge Function `consultar-biblioteca` |
| Asistente IA (GPT-4o-mini) | ✅ Completo | Edge Function `asistente-ia` + auditoría |
| Recetas con alertas de alergias | ✅ Completo | `RecetaModal.tsx` reutilizable |
| Dashboard médico con stats reales | ✅ Completo | Pacientes, citas hoy, recetas, consultas semana |
| Citas — agenda completa | ✅ Completo | Estados: pendiente, confirmada, en_curso, completada, cancelada, no_show |
| Pacientes — CRUD completo | ✅ Completo | Detalle con tabs Consultas y Signos Vitales |
| Facturas — crear, vista previa, enviar | ✅ Completo | Email/descargar/imprimir |
| Reportes — 5 tabs | ✅ Completo | Ingresos, Citas, Pacientes, Recetas, Facturación |
| Farmacias — buscador | ✅ Completo | Filtro por categoría |
| Notificaciones in-app | ✅ Completo | Tabla `notificaciones`, badge, marcar leídas |
| Dispensar receta | ✅ Completo | `registrar-dispensacion` Edge Function |
| Verificar receta QR | ✅ Completo | `verificar-receta-qr` Edge Function |
| Disponibilidad de visitas | ✅ Completo | `/disponibilidad-visitas` |
| Login/Registro médico | ✅ Completo | Con selector de país (Fase 7) |

### 2. Panel de Clínica (`src/clinica/pages/`)

| Funcionalidad | Estado | Notas |
|--------------|--------|-------|
| Dashboard clínica | ✅ Completo | `ClinicaDashboardPage.tsx` |
| Gestión de personal | ✅ Completo | `ClinicaPersonalPage.tsx` |
| Invitar médicos | ✅ Completo | `ClinicaInvitarMedicoPage.tsx` + Edge Functions |
| Invitar staff | ✅ Completo | `ClinicaInvitarStaffPage.tsx` + Edge Functions |
| Sistema de invitaciones por token | ✅ Completo | 6 Edge Functions de validación/registro |

### 3. Portal de Proveedores (`src/proveedor/`)

| Funcionalidad | Estado | Notas |
|--------------|--------|-------|
| Auth (login/registro) | ✅ Completo | Roles: admin, editor, visitador_medico |
| Dashboard con estadísticas reales | ✅ Completo | `useProveedorStats` — productos, visitas, campañas, pagos |
| Productos — CRUD completo | ✅ Completo | Catálogo con imágenes |
| Visitador médico — planes y agendado | ✅ Completo | `VisitadorPlanesPage`, `VisitadorAgendarPage` |
| Mis visitas / Ruta del día | ✅ Completo | Mapa Leaflet + navegación Google Maps/Waze |
| Check-in/check-out con foto + GPS | ✅ Completo | Bucket `evidencias-visitas` |
| Aprobación de visitas | ✅ Completo | Consume créditos del plan |
| Reporte de visitas | ✅ Completo | `ProveedorReporteVisitasPage.tsx` |
| Publicidad — planes y campañas | ✅ Completo | `PublicidadPlanesPage.tsx` carga desde BD |
| Métricas de campañas | ✅ Completo | `PublicidadMetricasPage.tsx` |
| Perfil editable | ✅ Completo | `ProveedorPerfilPage.tsx` con formulario completo |
| Pagos — historial real | ✅ Completo | `ProveedorPagosPage.tsx` con tabla de `pagos_proveedor` |
| Checkout de pagos | ✅ Completo | `PagoCheckoutPage.tsx` |
| Notificaciones con badge | ✅ Completo | Badge rojo en sidebar + página de notificaciones |
| Geocodificación | ✅ Completo | Google Maps + Nominatim fallback |
| Invitación visitadores por WhatsApp | ✅ Completo | Token + link de registro |
| Ubicaciones de médicos | ✅ Completo | `AdminUbicacionesMedicosPage.tsx` |

### 4. Portal del Paciente (`src/webapp/`)

| Funcionalidad | Estado | Notas |
|--------------|--------|-------|
| Auth (registro/login/logout) | ✅ Completo | Con selector de país (Fase 7) |
| Dashboard con contadores | ✅ Completo | Próximas citas, recetas activas, exámenes |
| Citas (tabs: Próximas/Pasadas/Canceladas) | ✅ Completo | Compatible con estados del panel médico |
| Recetas expandibles | ✅ Completo | Items de medicamentos con dosis/frecuencia |
| Exámenes con adjuntos | ✅ Completo | Resultados y archivos |
| Historial médico (línea de tiempo) | ✅ Completo | `WebAppHistorial.tsx` — 233 líneas, combina citas+recetas+exámenes |
| Chat en tiempo real | ✅ Completo | Supabase Realtime, burbujas con estado |
| Notificaciones (dropdown + badge) | ✅ Completo | Realtime, marcar leídas |
| Perfil editable | ✅ Completo | Nombre, teléfono, alergias, emergencia, etc. |

### 5. Panel Admin Maestro (`src/pages/admin-ezpay/`)

| Funcionalidad | Estado | Notas |
|--------------|--------|-------|
| Dashboard admin | ✅ Completo | Stats por país, ingresos, gráficos |
| Gestión de países | ✅ Completo | `PaisesPage.tsx` + 19 países LATAM insertados |
| Gestión de usuarios | ✅ Completo | Filtrado por país activo |
| Gestión de roles y permisos | ✅ Completo | |
| Finanzas y reportes | ✅ Completo | `ReportesFinancierosPage.tsx` |
| Empresas proveedoras | ✅ Completo | Filtrado por país |
| Visitas de proveedores | ✅ Completo | `AdminVisitasProveedoresPage.tsx` |
| Solicitudes de campaña | ✅ Completo | `SolicitudesCampanaPage.tsx` |
| Configuración de planes por país | ✅ Completo | 7 páginas de config (Médico, Clínica, Lab, Visitador, Farmacéutico, Farmacia, Empresas Afines) |
| Configuración de publicidad por país | ✅ Completo | `PlanesPublicidadConfigPage.tsx` |
| Notificaciones admin | ✅ Completo | `NotificacionesAdminPage.tsx` |

### 6. Sistema de Planes y Precios (`src/pages/planes/`)

| Funcionalidad | Estado | Notas |
|--------------|--------|-------|
| Planes unificados por país | ✅ Completo | 7 tipos de planes con precios locales por país |
| Planes de publicidad por país | ✅ Completo | `planes_publicidad_config` con precios locales |
| Auto-configuración al crear país | ✅ Completo | Trigger `auto_configurar_planes_publicidad` |
| Checkout y asignaciones | ✅ Completo | `PlanCheckout.tsx` |
| Asignaciones admin | ✅ Completo | `PlanesAsignacionesPage.tsx` filtrado por país |
| Excepciones de precios | ✅ Completo | `PlanesExcepcionesPage.tsx` filtrado por país |

### 7. Infraestructura y Backend

| Componente | Estado | Notas |
|-----------|--------|-------|
| **Migraciones SQL** | ✅ 28 migraciones | ~3,297 líneas de SQL |
| **Edge Functions** | ✅ 29 funciones | Desplegadas en Supabase |
| **RLS por país** | ✅ Completo | 11 tablas con políticas `admin_pais` / `super_admin` |
| **Filtrado por país (frontend)** | ✅ Completo | Hooks `usePaisFiltro`, `usePaisActivo` |
| **Onboarding por país** | ✅ Completo | Selector de país en login y registro |
| **Sistema de invitaciones** | ✅ Completo | 2 tablas + 6 Edge Functions + 4 páginas frontend |
| **Recordatorios automáticos** | ✅ Completo | `programar-recordatorio` + `procesar-recordatorios` vía cron-job.org |
| **Notificaciones in-app + email** | ✅ Completo | `enviar-notificacion` + `notificar-email` |
| **PWA** | ✅ Completo | Service Worker, manifest, icons |

---

## ⚠️ LO QUE FALTA / PENDIENTE

### 🔴 Crítico para Producción

| # | Pendiente | Impacto | Acción requerida |
|---|-----------|---------|------------------|
| 1 | **Verificar dominio en Resend** | ✅ **COMPLETADO** — SPF/DMARC corregidos por Asura. `from` revertido a `no-reply@ezpayconnect.com` en 4 Edge Functions + API + frontend. Deployado a Supabase. | Click "Verify" en Resend dashboard para confirmar verificación final |
| 2 | **Verificar cron-job.org activo** | Si el job se desactiva, los recordatorios 24h dejan de funcionar | Revisar dashboard de cron-job.org manualmente |
| 3 | **Revisar logs de `procesar-recordatorios`** | Posibles errores silenciosos cada 15 min | Ir a Supabase Dashboard → Edge Functions → Logs |

### 🟡 Mejoras Funcionales (Media prioridad)

| # | Pendiente | Área | Esfuerzo estimado |
|---|-----------|------|-------------------|
| 4 | **Agendar citas desde el portal del paciente** | ✅ **COMPLETADO** — Modal en 2 pasos: seleccionar médico/clínica → fecha/hora/motivo. Guarda en `citas` con estado `pendiente` (con médico) o `solicitada` (sin médico). Notificación in-app al médico. Recordatorio automático 24h. | WebApp |
| 5 | **Notificaciones push del navegador** | ✅ **COMPLETADO** — Service Worker custom con `injectManifest`, Push API, tabla `push_subscriptions`, Edge Function `enviar-push` con `webpush-webcrypto`, toggle en dashboard, integrado en citas y chat. | WebApp + PWA |
| 6 | **Segmentación contextual por ruta de publicidad** | Proveedor | ~3-4h — Fase 5 estructura lista pero no filtra aún por ubicación/ruta |
| 7 | **Offline support para check-in** | Proveedor PWA | ~6-8h — IndexedDB + sync cuando hay conexión |

### 🟢 Optimizaciones y Deuda Técnica (Baja prioridad)

| # | Pendiente | Área | Esfuerzo estimado |
|---|-----------|------|-------------------|
| 8 | **Code splitting** — Bundle principal es 2.2MB | Frontend | ~4-6h — Dynamic imports para reducir chunk inicial |
| 9 | **Service Worker cachea versiones viejas** | PWA | ~2-3h — Estrategia de cacheo más inteligente |
| 10 | **Duplicidad de tablas de países** | DB | ~2h — `paises` (legacy) vs `configuracion_pais` (nueva). Limpiar legacy |
| 11 | **Edge Function `enviar-recordatorio` legacy** | Backend | ~1h — Usa tabla `recordatorios_citas` (no existe), migrar a `recordatorios` |
| 12 | **Vistas faltantes en migraciones** | DB | ~2h — `v_pacientes_actividad`, `v_resumen_mensual`, `v_estadisticas_medico` |

---

## 📅 CALENDARIO DE TRABAJO PROPUESTO

### Semana 1 (Inmediata)

| Día | Tarea | Responsable | Entregable |
|-----|-------|-------------|------------|
| **Lunes** | Verificar DNS Resend + confirmar con Asura | Externo (Asura) | SPF corregido + DMARC agregado |
| **Lunes** | Revisar logs de `procesar-recordatorios` | Dev | Reporte de errores (si hay) |
| **Martes** | Click "Verify" en Resend + revertir `from` a `no-reply@ezpayconnect.com` | Dev | Dominio verificado en Resend |
| **Martes** | Verificar cron-job.org sigue activo | Dev | Confirmación de job funcionando |
| **Miércoles** | Implementar agendar citas desde portal paciente | Dev | `WebAppAgendarCita.tsx` funcional |
| **Jueves-Viernes** | Notificaciones push del navegador | Dev | Push API + Service Worker + suscripciones en BD |

### Semana 2

| Día | Tarea | Entregable |
|-----|-------|------------|
| **Lunes-Martes** | Segmentación contextual por ruta de publicidad | Filtro por ubicación GPS en campañas |
| **Miércoles-Jueves** | Code splitting + optimización de bundle | Bundle < 1MB inicial |
| **Viernes** | Offline support para check-in (MVP) | Check-in guarda en IndexedDB, sync al recuperar conexión |

### Semana 3 (Deuda técnica)

| Día | Tarea | Entregable |
|-----|-------|------------|
| **Lunes** | Limpiar tabla `paises` legacy | Solo queda `configuracion_pais` |
| **Martes** | Migrar `enviar-recordatorio` a tabla `recordatorios` | Edge Function actualizada y deployada |
| **Miércoles** | Crear vistas faltantes en migraciones | `v_pacientes_actividad`, `v_resumen_mensual`, `v_estadisticas_medico` |
| **Jueves-Viernes** | Cacheo inteligente del Service Worker | PWA no requiere hard refresh |

---

## 📊 Métricas del Proyecto

| Métrica | Valor |
|---------|-------|
| **Líneas de código SQL (migraciones)** | ~3,297 |
| **Migraciones aplicadas** | 28 |
| **Edge Functions desplegadas** | 29 |
| **Páginas del panel médico** | ~22 |
| **Páginas del portal proveedor** | ~21 |
| **Páginas del portal paciente** | ~9 + layout |
| **Páginas del panel clínica** | ~4 |
| **Hooks principales** | ~30 |
| **Países configurados** | 19 (LATAM) |
| **Commits en main** | 8+ fases completadas |
| **Deploys a Vercel** | Activos |
| **Bundle principal** | 2.2 MB (pendiente optimizar) |

---

## 🎯 Estado General

> **~90% del producto MVP está implementado y funcional.**

Los portales médico, proveedor y paciente están **operativos con datos reales**. Las funcionalidades críticas de negocio (consultas, recetas, citas, facturas, visitadores, campañas publicitarias, pagos, notificaciones, recordatorios) **funcionan en producción**.

Los pendientes son principalmente:
1. **Infraestructura externa** (Resend DNS, cron-job.org)
2. **Mejoras de UX** (agendar citas desde paciente, notificaciones push)
3. **Optimizaciones técnicas** (bundle size, offline, deuda técnica)

**El proyecto está listo para operación con usuarios reales una vez se resuelva la verificación de dominio en Resend.**
