// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - UTILIDADES DE PLANES (Latinoamérica completa)
// ═══════════════════════════════════════════════════════════════

import type { PlanConfiguracion, PlanFeature } from '@/types/planes';

// Tipo local para todos los países soportados
type PaisCodigoLocal = 'GT' | 'SV' | 'HN' | 'CR' | 'NI' | 'PA' | 'BZ' | 'MX' | 'DO' | 'CU' | 'PR' | 'CO' | 'VE' | 'EC' | 'PE' | 'BO' | 'CL' | 'AR' | 'PY' | 'UY' | 'BR' | 'GY' | 'SR' | 'GF' | 'US' | 'CA' | 'ES';

export function generarFeaturesPlan(config: PlanConfiguracion): PlanFeature[] {
  return [
    { label: 'Precio base', included: true, value: config.plan_base?.precio_base, icon: 'DollarSign' },
    { label: 'Precio local', included: true, value: config.precio_local, icon: 'DollarSign' },
    { label: 'Comisión', included: (config.comision_aplicada || 0) > 0, value: `${config.comision_aplicada || 0}%`, icon: 'Percent' },
    { label: 'Descuento', included: (config.descuento_porcentaje || 0) > 0, value: `${config.descuento_porcentaje || 0}%`, icon: 'Tag' },
  ];
}

export function formatearPrecio(precio: number, moneda: string): string {
  // Mapeo completo de monedas latinoamericanas + España/USA/Canadá
  const monedaMap: Record<string, string> = {
    // Centroamérica
    'QUETZAL': 'GTQ',
    'QUETZALES': 'GTQ',
    'GTQ': 'GTQ',
    'DOLLAR': 'USD',
    'DOLAR': 'USD',
    'DOLARES': 'USD',
    'DOLLARS': 'USD',
    'USD': 'USD',
    'LEMPIRA': 'HNL',
    'LEMPIRAS': 'HNL',
    'HNL': 'HNL',
    'COLON': 'CRC',           // Costa Rica
    'COLONES': 'CRC',         // Costa Rica
    'CRC': 'CRC',
    'COLON_SV': 'SVC',        // El Salvador (histórico, ahora usa USD)
    'SVC': 'SVC',
    'CORDOBA': 'NIO',         // Nicaragua
    'CORDOBAS': 'NIO',
    'NIO': 'NIO',
    'BALBOA': 'PAB',          // Panamá
    'BALBOAS': 'PAB',
    'PAB': 'PAB',
    'BZD': 'BZD',             // Belice
    
    // Caribe
    'PESO_MX': 'MXN',         // México
    'PESO_MEXICANO': 'MXN',
    'MXN': 'MXN',
    'PESO_DO': 'DOP',         // República Dominicana
    'PESO_DOMINICANO': 'DOP',
    'DOP': 'DOP',
    'PESO_CU': 'CUP',         // Cuba
    'CUP': 'CUP',
    'PESO_PR': 'USD',         // Puerto Rico usa USD
    
    // Sudamérica
    'PESO_CO': 'COP',         // Colombia
    'PESO_COLOMBIANO': 'COP',
    'COP': 'COP',
    'BOLIVAR': 'VES',         // Venezuela
    'BOLIVARES': 'VES',
    'VES': 'VES',
    'VEF': 'VEF',             // Venezuela (viejo)
    'DOLAR_EC': 'USD',        // Ecuador usa USD
    'SOL': 'PEN',             // Perú
    'SOLES': 'PEN',
    'PEN': 'PEN',
    'BOLIVIANO': 'BOB',       // Bolivia
    'BOLIVIANOS': 'BOB',
    'BOB': 'BOB',
    'PESO_CL': 'CLP',         // Chile
    'PESO_CHILENO': 'CLP',
    'CLP': 'CLP',
    'PESO_AR': 'ARS',         // Argentina
    'PESO_ARGENTINO': 'ARS',
    'ARS': 'ARS',
    'GUARANI': 'PYG',         // Paraguay
    'GUARANIES': 'PYG',
    'PYG': 'PYG',
    'PESO_UY': 'UYU',         // Uruguay
    'PESO_URUGUAYO': 'UYU',
    'UYU': 'UYU',
    'REAL': 'BRL',            // Brasil
    'REAIS': 'BRL',
    'BRL': 'BRL',
    'DOLAR_GY': 'GYD',        // Guyana
    'GYD': 'GYD',
    'DOLAR_SR': 'SRD',        // Surinam
    'SRD': 'SRD',
    'EURO_GF': 'EUR',         // Guayana Francesa
    
    // Norteamérica / Europa
    'CAD': 'CAD',             // Canadá
    'EUR': 'EUR',             // España / Europa
  };

  // Normalizar la moneda
  const monedaNormalizada = monedaMap[moneda?.toUpperCase()] || moneda?.toUpperCase() || 'USD';

  // Lista de monedas válidas para Intl.NumberFormat
  const monedasValidas = [
    'GTQ', 'USD', 'HNL', 'CRC', 'SVC', 'NIO', 'PAB', 'BZD',
    'MXN', 'DOP', 'CUP',
    'COP', 'VES', 'VEF', 'PEN', 'BOB', 'CLP', 'ARS', 'PYG', 'UYU', 'BRL', 'GYD', 'SRD',
    'CAD', 'EUR', 'GBP'
  ];
  const monedaFinal = monedasValidas.includes(monedaNormalizada) ? monedaNormalizada : 'USD';

  // Locale por moneda
  const localeMap: Record<string, string> = {
    'GTQ': 'es-GT', 'USD': 'en-US', 'HNL': 'es-HN', 'CRC': 'es-CR',
    'SVC': 'es-SV', 'NIO': 'es-NI', 'PAB': 'es-PA', 'BZD': 'en-BZ',
    'MXN': 'es-MX', 'DOP': 'es-DO', 'CUP': 'es-CU',
    'COP': 'es-CO', 'VES': 'es-VE', 'VEF': 'es-VE', 'PEN': 'es-PE',
    'BOB': 'es-BO', 'CLP': 'es-CL', 'ARS': 'es-AR', 'PYG': 'es-PY',
    'UYU': 'es-UY', 'BRL': 'pt-BR', 'GYD': 'en-GY', 'SRD': 'nl-SR',
    'CAD': 'en-CA', 'EUR': 'es-ES', 'GBP': 'en-GB'
  };

  try {
    const formato = new Intl.NumberFormat(
      localeMap[monedaFinal] || 'es-419',
      { style: 'currency', currency: monedaFinal, minimumFractionDigits: 2 }
    );
    return formato.format(precio);
  } catch (error) {
    // Fallback manual con símbolos conocidos
    const simbolos: Record<string, string> = {
      'GTQ': 'Q', 'USD': '$', 'HNL': 'L', 'CRC': '₡', 'SVC': '₡', 'NIO': 'C$',
      'PAB': 'B/.', 'BZD': 'BZ$',
      'MXN': '$', 'DOP': 'RD$', 'CUP': '$',
      'COP': '$', 'VES': 'Bs.', 'VEF': 'Bs.F', 'PEN': 'S/', 'BOB': 'Bs.',
      'CLP': '$', 'ARS': '$', 'PYG': '₲', 'UYU': '$', 'BRL': 'R$',
      'GYD': '$', 'SRD': '$',
      'CAD': 'C$', 'EUR': '€', 'GBP': '£'
    };
    const simbolo = simbolos[monedaFinal] || '$';
    return `${simbolo}${precio.toFixed(2)} ${monedaFinal}`;
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
  const nombres: Record<PaisCodigoLocal, string> = {
    GT: 'Guatemala', SV: 'El Salvador', HN: 'Honduras', CR: 'Costa Rica',
    NI: 'Nicaragua', PA: 'Panamá', BZ: 'Belice', MX: 'México',
    DO: 'República Dominicana', CU: 'Cuba', PR: 'Puerto Rico',
    CO: 'Colombia', VE: 'Venezuela', EC: 'Ecuador', PE: 'Perú',
    BO: 'Bolivia', CL: 'Chile', AR: 'Argentina', PY: 'Paraguay',
    UY: 'Uruguay', BR: 'Brasil', GY: 'Guyana', SR: 'Surinam',
    GF: 'Guayana Francesa', US: 'Estados Unidos', CA: 'Canadá',
    ES: 'España'
  };
  return nombres[codigo] || codigo;
}

export function getBanderaPais(codigo: PaisCodigoLocal): string {
  const banderas: Record<PaisCodigoLocal, string> = {
    GT: '🇬🇹', SV: '🇸🇻', HN: '🇭🇳', CR: '🇨🇷', NI: '🇳🇮', PA: '🇵🇦', BZ: '🇧🇿',
    MX: '🇲🇽', DO: '🇩🇴', CU: '🇨🇺', PR: '🇵🇷',
    CO: '🇨🇴', VE: '🇻🇪', EC: '🇪🇨', PE: '🇵🇪', BO: '🇧🇴', CL: '🇨🇱', AR: '🇦🇷',
    PY: '🇵🇾', UY: '🇺🇾', BR: '🇧🇷', GY: '🇬🇾', SR: '🇸🇷', GF: '🇬🇫',
    US: '🇺🇸', CA: '🇨🇦', ES: '🇪🇸'
  };
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