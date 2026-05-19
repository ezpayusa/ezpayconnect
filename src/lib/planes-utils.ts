// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - UTILIDADES DE PLANES
// ═══════════════════════════════════════════════════════════════

import type { PlanConfiguracion, PlanFeature } from '@/types/planes';

// Tipo local para evitar problemas de importación con Vite
type PaisCodigoLocal = 'GT' | 'SV' | 'HN';

export function generarFeaturesPlan(config: PlanConfiguracion): PlanFeature[] {
  return [
    { label: 'Precio base', included: true, value: config.plan_base?.precio_base, icon: 'DollarSign' },
    { label: 'Precio local', included: true, value: config.precio_local, icon: 'DollarSign' },
    { label: 'Comisión', included: (config.comision_aplicada || 0) > 0, value: `${config.comision_aplicada || 0}%`, icon: 'Percent' },
    { label: 'Descuento', included: (config.descuento_porcentaje || 0) > 0, value: `${config.descuento_porcentaje || 0}%`, icon: 'Tag' },
  ];
}

export function formatearPrecio(precio: number, moneda: string): string {
  // Mapeo de monedas comunes que pueden venir mal escritas
  const monedaMap: Record<string, string> = {
    'COLON': 'GTQ',
    'COLONES': 'GTQ',
    'QUETZAL': 'GTQ',
    'QUETZALES': 'GTQ',
    'DOLLAR': 'USD',
    'DOLAR': 'USD',
    'DOLARES': 'USD',
    'DOLLARS': 'USD',
    'LEMPIRA': 'HNL',
    'LEMPIRAS': 'HNL',
    'COLON_SV': 'SVC',
    'CORDOBA': 'NIO',
    'CORDOBAS': 'NIO',
    'BALBOA': 'PAB',
    'BALBOAS': 'PAB',
  };

  // Normalizar la moneda
  const monedaNormalizada = monedaMap[moneda?.toUpperCase()] || moneda?.toUpperCase() || 'USD';

  // Lista de monedas válidas para Intl.NumberFormat
  const monedasValidas = ['GTQ', 'USD', 'HNL', 'SVC', 'NIO', 'PAB', 'EUR', 'MXN'];
  const monedaFinal = monedasValidas.includes(monedaNormalizada) ? monedaNormalizada : 'USD';

  try {
    const formato = new Intl.NumberFormat(
      monedaFinal === 'GTQ' ? 'es-GT' : monedaFinal === 'USD' ? 'en-US' : 'es-SV',
      { style: 'currency', currency: monedaFinal, minimumFractionDigits: 2 }
    );
    return formato.format(precio);
  } catch (error) {
    // Fallback si Intl falla por cualquier razón
    return `$${precio.toFixed(2)} ${moneda}`;
  }
}

export function getColorPlan(tipo: string): string {
  const colores: Record<string, string> = {
    basico: '#22c55e',
    profesional: '#3b82f6',
    enterprise: '#8b5cf6',
    medico: '#1E5C8E',
    clinica: '#f59e0b',
    lab: '#ef4444',
    visitador: '#10b981',
    farmaceutico: '#0d9488',
    farmacia: '#e11d48',
    publicidad: '#d97706',
    empresas_afines: '#4f46e5',
  };
  return colores[tipo] || '#64748b';
}

export function getNombrePais(codigo: PaisCodigoLocal): string {
  const nombres: Record<PaisCodigoLocal, string> = { GT: 'Guatemala', SV: 'El Salvador', HN: 'Honduras' };
  return nombres[codigo] || codigo;
}

export function getBanderaPais(codigo: PaisCodigoLocal): string {
  const banderas: Record<PaisCodigoLocal, string> = { GT: '🇬🇹', SV: '🇸🇻', HN: '🇭🇳' };
  return banderas[codigo] || '🌎';
}

export function getEstadoConfig(estado: string): { label: string; color: string; bg: string } {
  const configs: Record<string, { label: string; color: string; bg: string }> = {
    activo: { label: 'Activo', color: 'text-green-700', bg: 'bg-green-100' },
    inactivo: { label: 'Inactivo', color: 'text-gray-700', bg: 'bg-gray-100' },
    pendiente: { label: 'Pendiente', color: 'text-yellow-700', bg: 'bg-yellow-100' },
    suspendido: { label: 'Suspendido', color: 'text-red-700', bg: 'bg-red-100' },
    cancelado: { label: 'Cancelado', color: 'text-red-700', bg: 'bg-red-100' },
  };
  return configs[estado] || { label: estado, color: 'text-gray-700', bg: 'bg-gray-100' };
}

export function diasRestantes(fechaFin: string | null): number {
  if (!fechaFin) return -1;
  const fin = new Date(fechaFin);
  const hoy = new Date();
  const diff = fin.getTime() - hoy.getTime();
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
}

export function expiraPronto(fechaFin: string | null, diasAlerta: number = 7): boolean {
  const dias = diasRestantes(fechaFin);
  return dias >= 0 && dias <= diasAlerta;
}
