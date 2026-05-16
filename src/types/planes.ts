// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - TIPOS DE PLANES MÉDICO
// ═══════════════════════════════════════════════════════════════

export type PaisCodigo = 'GT' | 'SV' | 'HN';

export type TipoPlan = 'basico' | 'profesional' | 'enterprise';

export type EstadoPlan = 'activo' | 'inactivo' | 'pendiente' | 'suspendido' | 'cancelado';

export type TipoCiclo = 'mensual' | 'anual';

export type TipoSoporte = 'email' | 'chat' | 'telefono' | 'dedicado';

export type TipoExcepcion = 'descuento_porcentaje' | 'descuento_fijo' | 'precio_custom' | 'trial_extendido';

export type TipoCambioPlan = 'upgrade' | 'downgrade' | 'renovacion' | 'cancelacion' | 'activacion';

// ── Plan Base ─────────────────────────────────────────────────
export interface PlanBase {
  id: string;
  nombre: string;
  codigo: TipoPlan;
  descripcion: string;
  icono: string;
  color: string;
  orden: number;
  activo: boolean;
  created_at?: string;
  updated_at?: string;
}

// ── Configuración por País ────────────────────────────────────
export interface PlanConfiguracion {
  id: string;
  plan_id: string;
  pais_codigo: PaisCodigo;
  precio_mensual: number;
  precio_anual: number;
  moneda: string; // GTQ, USD
  max_medicos: number;
  max_pacientes: number;
  max_citas_mes: number;
  incluye_recetas: boolean;
  incluye_facturacion: boolean;
  incluye_farmacias: boolean;
  incluye_reportes_avanzados: boolean;
  incluye_whatsapp: boolean;
  incluye_api: boolean;
  soporte_tipo: TipoSoporte;
  created_at?: string;
  updated_at?: string;
  // Relaciones
  plan_base?: PlanBase;
}

// ── Asignación a Médico ───────────────────────────────────────
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

// ── Excepción / Promoción ─────────────────────────────────────
export interface PlanExcepcion {
  id: string;
  medico_id: string | null; // null = promoción global
  plan_config_id: string;
  tipo: TipoExcepcion;
  valor: number;
  fecha_inicio: string;
  fecha_fin: string | null;
  motivo: string;
  creado_por: string;
  activo: boolean;
  created_at?: string;
  updated_at?: string;
  // Relaciones
  plan_configuracion?: PlanConfiguracion;
  medico?: {
    id: string;
    nombre: string;
    email: string;
  };
  creador?: {
    id: string;
    nombre: string;
  };
}

// ── Historial de Cambios ──────────────────────────────────────
export interface PlanHistorial {
  id: string;
  medico_id: string;
  plan_anterior_id: string | null;
  plan_nuevo_id: string | null;
  tipo_cambio: TipoCambioPlan;
  precio_anterior: number | null;
  precio_nuevo: number | null;
  moneda: string;
  motivo: string;
  realizado_por: string;
  created_at?: string;
  // Relaciones
  plan_anterior?: PlanConfiguracion;
  plan_nuevo?: PlanConfiguracion;
  medico?: {
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
  nombre: string;
  codigo: TipoPlan;
  descripcion: string;
  icono: string;
  color: string;
  orden: number;
}

export interface CrearPlanConfigDTO {
  plan_id: string;
  pais_codigo: PaisCodigo;
  precio_mensual: number;
  precio_anual: number;
  moneda: string;
  max_medicos: number;
  max_pacientes: number;
  max_citas_mes: number;
  incluye_recetas: boolean;
  incluye_facturacion: boolean;
  incluye_farmacias: boolean;
  incluye_reportes_avanzados: boolean;
  incluye_whatsapp: boolean;
  incluye_api: boolean;
  soporte_tipo: TipoSoporte;
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
  medico_id: string | null;
  plan_config_id: string;
  tipo: TipoExcepcion;
  valor: number;
  fecha_inicio: string;
  fecha_fin?: string;
  motivo: string;
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
