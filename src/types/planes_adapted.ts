// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - TIPOS DE PLANES MÉDICO (ADAPTADO A ESTRUCTURA EXISTENTE)
// ═══════════════════════════════════════════════════════════════

export type PaisCodigo = 'GT' | 'SV' | 'HN';

export type TipoPlan = 'basico' | 'profesional' | 'enterprise';

export type TipoEntidad = 'medico' | 'clinica' | 'lab' | 'visitador';

export type EstadoPlan = 'activo' | 'inactivo' | 'pendiente' | 'suspendido' | 'cancelado';

export type TipoCiclo = 'mensual' | 'anual';

export type TipoSoporte = 'email' | 'chat' | 'telefono' | 'dedicado';

export type TipoExcepcion = 'descuento_porcentaje' | 'descuento_fijo' | 'precio_custom' | 'trial_extendido';

export type TipoCambioPlan = 'upgrade' | 'downgrade' | 'renovacion' | 'cancelacion' | 'activacion';

// ── Plan Base (adaptado a estructura existente) ───────────────
export interface PlanBase {
  id: string;
  tipo: string;           // 'medico', 'clinica', 'lab', 'visitador'
  nombre: string;
  descripcion: string;
  precio_base: number;
  moneda: string;
  periodicidad: string;   // 'mensual', 'anual'
  activo: boolean;
  created_at?: string;
  // Campos virtuales para compatibilidad con UI
  codigo?: string;
  icono?: string;
  color?: string;
  orden?: number;
}

// ── País (referencia para pais_id) ────────────────────────────
export interface Pais {
  id: string;
  codigo: PaisCodigo;
  nombre: string;
  moneda: string;
  comision_porcentaje: number;
  activo: boolean;
}

// ── Configuración por País (adaptado a estructura existente) ──
export interface PlanConfiguracion {
  id: string;
  plan_base_id: string;
  pais_id: string;
  precio_local: number;
  comision_aplicada: number;
  descuento_porcentaje: number;
  activo: boolean;
  created_at?: string;
  // Relaciones
  plan_base?: PlanBase;
  pais?: Pais;
  // Campos virtuales calculados para UI
  precio_mensual?: number;
  precio_anual?: number;
  moneda?: string;
  max_medicos?: number;
  max_pacientes?: number;
  max_citas_mes?: number;
  incluye_recetas?: boolean;
  incluye_facturacion?: boolean;
  incluye_farmacias?: boolean;
  incluye_reportes_avanzados?: boolean;
  incluye_whatsapp?: boolean;
  incluye_api?: boolean;
  soporte_tipo?: TipoSoporte;
}

// ── Asignación a Médico (NUEVA TABLA - no existía) ────────────
export interface PlanAsignacion {
  id: string;
  medico_id: string;
  plan_config_id: string;
  fecha_inicio: string;
  fecha_fin: string | null;
  tipo_ciclo: TipoCiclo;
  precio_aplicado: number;
  moneda: string;
  estado: EstadoPlan;
  metodo_pago: string | null;
  referencia_pago: string | null;
  auto_renovar: boolean;
  created_at?: string;
  updated_at?: string;
  // Relaciones
  plan_configuracion?: PlanConfiguracion;
  medico?: {
    id: string;
    nombre: string;
    email: string;
    especialidad?: string;
  };
}

// ── Excepción / Promoción (adaptado a estructura existente) ────
export interface PlanExcepcion {
  id: string;
  plan_config_id: string;
  entidad_id: string | null;    // null = promoción global
  tipo_entidad: string | null;  // 'medico', 'clinica', etc.
  precio_especial: number;
  comision_especial: number;
  motivo: string;
  fecha_inicio: string;
  fecha_fin: string | null;
  activo: boolean;
  created_at?: string;
  // Relaciones
  plan_configuracion?: PlanConfiguracion;
  entidad?: {
    id: string;
    nombre: string;
    email: string;
  };
}

// ── Historial de Cambios (adaptado a estructura existente) ────
export interface PlanHistorial {
  id: string;
  entidad_id: string;
  tipo_entidad: string;
  plan_config_id: string;
  accion: string;           // 'upgrade', 'downgrade', 'renovacion', 'cancelacion', 'activacion'
  detalle: Record<string, any>;  // JSONB: { precio_anterior, precio_nuevo, moneda, motivo }
  usuario_admin_id: string;
  created_at?: string;
  // Relaciones
  plan_configuracion?: PlanConfiguracion;
  entidad?: {
    id: string;
    nombre: string;
    email: string;
  };
  ejecutor?: {
    id: string;
    nombre: string;
  };
}

// ── DTOs para creación/actualización ──────────────────────────
export interface CrearPlanBaseDTO {
  tipo: string;
  nombre: string;
  descripcion: string;
  precio_base: number;
  moneda: string;
  periodicidad: string;
}

export interface CrearPlanConfigDTO {
  plan_base_id: string;
  pais_id: string;
  precio_local: number;
  comision_aplicada: number;
  descuento_porcentaje: number;
}

export interface CrearPlanAsignacionDTO {
  medico_id: string;
  plan_config_id: string;
  fecha_inicio: string;
  fecha_fin?: string;
  tipo_ciclo: TipoCiclo;
  precio_aplicado: number;
  moneda: string;
  auto_renovar: boolean;
}

export interface CrearPlanExcepcionDTO {
  plan_config_id: string;
  entidad_id: string | null;
  tipo_entidad: string | null;
  precio_especial: number;
  comision_especial: number;
  motivo: string;
  fecha_inicio: string;
  fecha_fin?: string;
}

// ── Filtros ───────────────────────────────────────────────────
export interface FiltrosPlanes {
  pais?: PaisCodigo;
  estado?: EstadoPlan;
  tipo?: TipoPlan;
  search?: string;
}

// ── Feature list para UI ─────────────────────────────────────
export interface PlanFeature {
  label: string;
  included: boolean;
  value?: string | number;
  icon?: string;
}
