export type AdminRole = 'super_admin' | 'admin_pais' | 'admin_finanzas' | 'admin_soporte' | 'admin_ventas';

export interface AdminUser {
  id: string;
  email: string;
  nombre: string;
  rol: AdminRole;
  pais_id?: string;
  activo: boolean;
  created_at: string;
}

export interface AdminStats {
  total_medicos: number;
  total_clinicas: number;
  total_ingresos_mes: number;
  total_transacciones: number;
  medicos_nuevos_mes: number;
}

export interface PaisConfig {
  id: string;
  codigo: string;
  nombre: string;
  moneda: string;
  comisiones_activas: boolean;
  porcentaje_comision_default: number;
  activo: boolean;
}
