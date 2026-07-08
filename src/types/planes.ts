// src/types/planes.ts
// Tipos para el módulo de Planes Médicos y Clínicas

export type TipoPlan = 'medico' | 'clinica' | 'visitador' | 'publicidad' | 'farmacia' | 'farmaceutico' | 'empresas_afines' | 'lab' | 'otros';
export type EstadoPlan = 'activo' | 'inactivo' | 'pendiente' | 'suspendido' | 'cancelado';
export type CicloFacturacion = 'mensual' | 'anual';
export type MetodoPago = 'tarjeta' | 'transferencia' | 'movil';

export interface PlanBase {
  id: string;
  nombre: string;
  descripcion: string;
  tipo: TipoPlan;
  precio_base: number; // Siempre en USD
  moneda: string;
  periodicidad: string;
  caracteristicas: string[];
  limite_pacientes?: number;
  limite_medicos?: number;
  limite_sucursales?: number;
  soporte_prioritario: boolean;
  personalizacion_logo: boolean;
  reportes_avanzados: boolean;
  api_acceso: boolean;
  popular?: boolean;
  activo: boolean;
  orden: number;
  atributos?: Record<string, any>;
  created_at?: string;
  updated_at?: string;
}

export interface PlanConfiguracion {
  id: string;
  plan_id: string;
  pais_id: string;
  pais_codigo?: string;
  moneda_local: string;
  precio_local: number;
  precio_anual?: number;
  impuesto_incluido: boolean;
  precio_impuestos?: number;
  ajuste_por_pais?: number;
  comision_aplicada?: number;
  descuento_porcentaje?: number;
  activo: boolean;
  created_at?: string;
  updated_at?: string;
  // Joins
  plan_base?: PlanBase;
  pais?: {
    id: string;
    nombre: string;
    codigo: string;
    moneda: string;
  };
}

export interface PlanExcepcion {
  id: string;
  plan_config_id?: string;
  plan_id?: string;
  pais_codigo?: string;
  tipo_usuario?: string;
  entidad_id?: string;
  descuento_porcentaje?: number;
  precio_especial?: number;
  fecha_inicio?: string;
  fecha_fin?: string;
  motivo?: string;
  activo: boolean;
  created_at?: string;
  // Joins
  plan_configuracion?: PlanConfiguracion;
}

export interface PlanAsignacion {
  id: string;
  usuario_id?: string;
  medico_id?: string;
  empresa_id?: string;
  plan_id?: string;
  plan_config_id?: string;
  configuracion_id?: string;
  estado: EstadoPlan;
  ciclo_facturacion?: CicloFacturacion;
  tipo_ciclo?: CicloFacturacion;
  metodo_pago?: MetodoPago;
  precio_final?: number;
  precio_aplicado?: number;
  moneda: string;
  fecha_inicio: string;
  fecha_fin?: string;
  fecha_cancelacion?: string;
  motivo_cancelacion?: string;
  renovacion_automatica?: boolean;
  auto_renovar?: boolean;
  // Joins
  plan_nombre?: string;
  plan_configuracion?: PlanConfiguracion;
  medico?: {
    id: string;
    nombre: string;
    email: string;
    especialidad?: string;
  };
  usuario?: {
    id: string;
    nombre: string;
    email: string;
  };
  created_at?: string;
  updated_at?: string;
}

export interface PlanHistorial {
  id: string;
  asignacion_id?: string;
  entidad_id?: string;
  tipo_entidad?: string;
  plan_config_id?: string;
  accion: string;
  detalle?: any;
  detalles?: string;
  fecha_accion?: string;
  usuario_admin_id?: string;
  created_at?: string;
}

export interface PlanPaisInfo {
  codigo: string;
  nombre: string;
  moneda: string;
  simbolo: string;
}

export interface PlanFeature {
  label: string;
  included: boolean;
  value?: any;
  icon?: string;
}

export interface Pais {
  id: string;
  nombre: string;
  codigo: string;
  moneda: string;
  simbolo?: string;
  activo?: boolean;
}

// DTOs para crear/actualizar
export interface CrearPlanBaseDTO {
  nombre: string;
  descripcion: string;
  tipo: TipoPlan;
  precio_base: number;
  moneda: string;
  periodicidad: string;
  activo?: boolean;
  caracteristicas?: string[];
  limite_pacientes?: number;
  limite_medicos?: number;
  limite_sucursales?: number;
  soporte_prioritario?: boolean;
  personalizacion_logo?: boolean;
  reportes_avanzados?: boolean;
  api_acceso?: boolean;
  popular?: boolean;
  orden?: number;
}

export interface CrearPlanConfigDTO {
  plan_base_id: string;
  pais_id: string;
  moneda_local?: string;
  precio_local: number;
  precio_anual?: number;
  impuesto_incluido?: boolean;
  precio_impuestos?: number;
  comision_aplicada?: number;
  descuento_porcentaje?: number;
}

export interface CrearPlanAsignacionDTO {
  medico_id?: string;
  usuario_id?: string;
  plan_config_id: string;
  plan_id?: string;
  configuracion_id?: string;
  precio_aplicado?: number;
  precio_final?: number;
  moneda: string;
  tipo_ciclo?: CicloFacturacion;
  ciclo_facturacion?: CicloFacturacion;
  metodo_pago?: MetodoPago;
  fecha_inicio?: string;
  fecha_fin?: string;
  auto_renovar?: boolean;
  renovacion_automatica?: boolean;
}

export interface CrearPlanExcepcionDTO {
  plan_config_id?: string;
  plan_id?: string;
  pais_codigo?: string;
  entidad_id?: string;
  tipo_usuario?: string;
  descuento_porcentaje?: number;
  precio_especial?: number;
  fecha_inicio?: string;
  fecha_fin?: string;
  motivo?: string;
}

export interface FiltrosPlanes {
  tipo?: TipoPlan;
  estado?: EstadoPlan;
  pais_id?: string;
  busqueda?: string;
}

// Helpers para joins
export interface PlanConConfiguracion extends PlanBase {
  configuraciones?: PlanConfiguracion[];
}

export interface ConfiguracionConPlan extends PlanConfiguracion {
  plan?: PlanBase;
}

export type PaisCodigo = 'GT' | 'SV' | 'HN';
export type TipoSoporte = 'email' | 'chat' | 'telefono' | 'dedicado';