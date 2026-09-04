import { supabase } from '@/lib/supabase'

// Acceso a datos del módulo comercial.
//
// DE DÓNDE SALE LA LISTA: de las policies de SELECT de la mig 264, que ya calculan el conjunto
// correcto con private.asesores_a_cargo() — asesor: él mismo; supervisor: su equipo + él;
// admin_pais: su país; super_admin: todo. Por eso NO hay ningún .eq('asesor_id') acá.
// Agregarlo sería una SEGUNDA definición de "de quién es la cartera", y además rompería al
// supervisor: le devolvería sólo lo propio y le escondería el equipo.
//
// Los dos únicos .eq del módulo son de otra naturaleza:
//   .eq('pais_id', paisId)      en la pantalla de admin — es un SELECTOR DE VISTA (esa ruta está
//                               parametrizada por :paisId y un super_admin ve varios países).
//                               Sólo puede achicar lo que la policy ya permitió.
//   .eq('prospecto_id', id)     al traer contactos — es la CLAVE DEL JOIN. El control es
//                               private.prospecto_visible() dentro de la policy.

export type Prospecto = {
  id: string
  nombre: string
  tipo: string
  estado_pipeline: string
  asesor_id: string
  pais_id: string
  direccion: string | null
  lat: number | null
  lng: number | null
  notas: string | null
  motivo_perdida: string | null
  empresa_proveedora_id: string | null
  updated_at: string
  asesor?: { nombre_completo: string | null } | null
}

export type Contacto = {
  id: string
  prospecto_id: string
  nombre: string
  puesto: string | null
  email: string | null
  telefono: string | null
  celular: string | null
  es_decisor: boolean
  notas: string | null
  activo: boolean
}

export type ItemCatalogo = { codigo: string; etiqueta: string; orden: number; es_terminal?: boolean }

const COLS =
  'id,nombre,tipo,estado_pipeline,asesor_id,pais_id,direccion,lat,lng,notas,motivo_perdida,' +
  'empresa_proveedora_id,updated_at,asesor:perfiles!prospectos_asesor_id_fkey(nombre_completo)'

/** Cartera del usuario. Sin filtro de asesor: lo pone la RLS. */
export async function listarProspectos() {
  return supabase.from('prospectos').select(COLS).order('updated_at', { ascending: false })
}

/** Igual, acotada al país de la ruta. El .eq es selector de vista, no permiso. */
export async function listarProspectosDePais(paisId: string) {
  return supabase.from('prospectos').select(COLS).eq('pais_id', paisId)
    .order('updated_at', { ascending: false })
}

export async function obtenerProspecto(id: string) {
  return supabase.from('prospectos').select(COLS).eq('id', id).maybeSingle()
}

/** El .eq es la clave del join; la visibilidad la impone prospecto_visible() en la policy. */
export async function listarContactos(prospectoId: string) {
  return supabase.from('prospecto_contactos').select('*').eq('prospecto_id', prospectoId)
    .order('created_at', { ascending: true })
}

export async function listarTipos() {
  return supabase.from('catalogo_prospecto_tipo').select('codigo,etiqueta,orden')
    .eq('activo', true).order('orden')
}

export async function listarEstados() {
  return supabase.from('catalogo_pipeline_estado').select('codigo,etiqueta,orden,es_terminal')
    .eq('activo', true).order('orden')
}

/** Asesores elegibles. La policy de asesores_perfil ya la acota al país / a la cartera. */
export async function listarAsesores() {
  return supabase.from('asesores_perfil')
    .select('id,codigo_asesor,activo,pais_id,perfil:perfiles!asesores_perfil_id_fkey(nombre_completo,rol)')
    .eq('activo', true).order('codigo_asesor')
}

// --- Escritura: las 7 RPCs de la mig 272. El front no escribe una tabla directamente. ----------

export async function crearProspecto(p: {
  nombre: string; tipo: string; asesorId: string
  direccion?: string | null; notas?: string | null
}) {
  return supabase.rpc('crear_prospecto', {
    p_nombre: p.nombre, p_tipo: p.tipo, p_asesor_id: p.asesorId,
    p_direccion: p.direccion ?? null, p_notas: p.notas ?? null,
  })
}

export async function actualizarProspecto(p: {
  id: string; nombre: string; tipo: string
  direccion: string | null; lat: number | null; lng: number | null
  notas: string | null; empresaProveedoraId: string | null
}) {
  return supabase.rpc('actualizar_prospecto', {
    p_prospecto_id: p.id, p_nombre: p.nombre, p_tipo: p.tipo,
    p_direccion: p.direccion, p_lat: p.lat, p_lng: p.lng,
    p_notas: p.notas, p_empresa_proveedora_id: p.empresaProveedoraId,
  })
}

export async function cambiarEstado(id: string, estado: string, motivoPerdida?: string | null) {
  return supabase.rpc('cambiar_estado_prospecto', {
    p_prospecto_id: id, p_estado: estado, p_motivo_perdida: motivoPerdida ?? null,
  })
}

export async function reasignarProspecto(id: string, asesorNuevoId: string) {
  return supabase.rpc('reasignar_prospecto', { p_prospecto_id: id, p_asesor_nuevo_id: asesorNuevoId })
}

export async function guardarContacto(p: {
  prospectoId: string; nombre: string; id?: string | null
  puesto?: string | null; email?: string | null; telefono?: string | null
  celular?: string | null; esDecisor?: boolean; notas?: string | null; activo?: boolean
}) {
  return supabase.rpc('upsert_contacto_prospecto', {
    p_prospecto_id: p.prospectoId, p_nombre: p.nombre, p_id: p.id ?? null,
    p_puesto: p.puesto ?? null, p_email: p.email ?? null, p_telefono: p.telefono ?? null,
    p_celular: p.celular ?? null, p_es_decisor: p.esDecisor ?? false,
    p_notas: p.notas ?? null, p_activo: p.activo ?? true,
  })
}

// ============================================================================================
// FRENTE VISITAS (migs 273/274/275)
// ============================================================================================
// Igual que arriba: ningún filtro de ownership en el cliente. Las policies de la 273/274 ya
// resuelven qué ve cada uno — el asesor lo suyo, el supervisor su cartera, el admin su país.

export type Jornada = {
  id: string
  fecha: string
  inicio_at: string
  inicio_lat: number | null
  inicio_lng: number | null
  inicio_precision_m: number | null
  fin_at: string | null
  notas_cierre: string | null
}

export type VisitaComercial = {
  id: string
  prospecto_id: string
  asesor_id: string
  pais_id: string
  jornada_id: string | null
  fecha_planificada: string
  estado: string
  checkin_at: string | null
  checkin_cliente_at: string | null
  checkin_origen: string
  checkin_lat: number | null
  checkin_lng: number | null
  checkin_precision_m: number | null
  checkin_distancia_m: number | null
  checkin_verificado: boolean
  checkin_motivo: string | null
  checkout_at: string | null
  prospecto?: { nombre: string; lat: number | null; lng: number | null } | null
}

export type ResultadoCheckin = {
  verificado: boolean
  distancia_m: number | null
  origen: string
  motivo: string | null
}

const COLS_VISITA =
  'id,prospecto_id,asesor_id,pais_id,jornada_id,fecha_planificada,estado,checkin_at,' +
  'checkin_cliente_at,checkin_origen,checkin_lat,checkin_lng,checkin_precision_m,' +
  'checkin_distancia_m,checkin_verificado,checkin_motivo,checkout_at,' +
  'prospecto:prospectos!visitas_comerciales_prospecto_id_fkey(nombre,lat,lng)'

/** La jornada de hoy, si existe. La RLS ya la acota al llamante. */
export async function jornadaDeHoy() {
  const hoy = new Date().toISOString().slice(0, 10)
  return supabase.from('jornadas_comerciales').select('*').eq('fecha', hoy).maybeSingle()
}

/** Visitas de una fecha. Sin .eq de asesor: lo pone la policy. */
export async function visitasDelDia(fecha: string) {
  return supabase.from('visitas_comerciales').select(COLS_VISITA)
    .eq('fecha_planificada', fecha).order('created_at', { ascending: true })
}

export async function obtenerVisita(id: string) {
  return supabase.from('visitas_comerciales').select(COLS_VISITA).eq('id', id).maybeSingle()
}

export async function reporteDeVisita(visitaId: string) {
  return supabase.from('reportes_visita').select('*').eq('visita_id', visitaId).maybeSingle()
}

export async function adjuntosDeVisita(visitaId: string) {
  return supabase.from('visita_adjuntos').select('*').eq('visita_id', visitaId)
    .order('created_at', { ascending: true })
}

export async function listarResultados() {
  return supabase.from('catalogo_resultado_visita').select('codigo,etiqueta,orden')
    .eq('activo', true).order('orden')
}

/** Umbrales EFECTIVOS: los mismos que aplica la RPC (mig 275), no una copia en el cliente. */
export async function configVisitasEfectiva() {
  return supabase.rpc('config_visitas_efectiva')
}

export async function abrirJornada(g: { lat: number | null; lng: number | null; precision_m: number | null }) {
  return supabase.rpc('abrir_jornada', { p_lat: g.lat, p_lng: g.lng, p_precision_m: g.precision_m })
}

export async function cerrarJornada(
  g: { lat: number | null; lng: number | null; precision_m: number | null }, notas: string | null) {
  return supabase.rpc('cerrar_jornada', {
    p_lat: g.lat, p_lng: g.lng, p_precision_m: g.precision_m, p_notas: notas,
  })
}

export async function planificarVisita(prospectoId: string, fecha: string) {
  return supabase.rpc('planificar_visita', { p_prospecto_id: prospectoId, p_fecha: fecha })
}

/**
 * Check-in. `p_cliente_at` va SIEMPRE en null: la cola diferida es su propio frente y mezclarla
 * acá escondería bugs de las dos. Sin red, esto falla — con un mensaje que lo dice.
 */
export async function checkinVisita(
  visitaId: string, g: { lat: number | null; lng: number | null; precision_m: number | null }) {
  return supabase.rpc('checkin_visita_comercial', {
    p_visita_id: visitaId, p_lat: g.lat, p_lng: g.lng,
    p_precision_m: g.precision_m, p_cliente_at: null,
  })
}

export async function checkoutVisita(visitaId: string, g: { lat: number | null; lng: number | null }) {
  return supabase.rpc('checkout_visita_comercial', {
    p_visita_id: visitaId, p_lat: g.lat, p_lng: g.lng,
  })
}

export async function guardarReporte(p: {
  visitaId: string; resultado: string; resumen: string
  compromisos?: string | null; proximaAccionFecha?: string | null
}) {
  return supabase.rpc('guardar_reporte_visita', {
    p_visita_id: p.visitaId, p_resultado: p.resultado, p_resumen: p.resumen,
    p_compromisos: p.compromisos ?? null, p_proxima_accion_fecha: p.proximaAccionFecha ?? null,
  })
}

// La subida de adjuntos vive en ./adjuntos.ts: necesita progreso real (XHR), validación previa y
// la compensación del huérfano, y todo eso junto no es "una llamada más" como el resto de este
// archivo. Se re-exporta para que las pantallas tengan un solo import.
export { subirAdjuntoVisita, urlFirmada, validarAdjunto, ACCEPT_ADJUNTO, MAX_BYTES_ADJUNTO } from './adjuntos'
