// Formateador único de montos (es-GT): la landing de planes de visitas, la gestión de planes y el checkout de
// plan_visitador muestran el mismo texto ("Q250.00").
//
// Según la versión de ICU, Intl separa el símbolo del número con un espacio duro ("Q 250.00") o no lo separa
// ("Q250.00"). Para que se vea igual en todos los navegadores, si la moneda tiene símbolo propio (Q, $) se quita el
// espacio; si Intl muestra el código ISO ("USD"), se deja un espacio común ("USD 250.00").
export function formatearMonto(monto: number, moneda: string): string {
  const codigo = (moneda || '').trim().toUpperCase()
  try {
    const partes = new Intl.NumberFormat('es-GT', { style: 'currency', currency: codigo }).formatToParts(monto)
    const simbolo = partes.find((p) => p.type === 'currency')?.value ?? ''
    const conCodigo = simbolo.toUpperCase() === codigo
    return partes
      .map((p) => (p.type === 'literal' && /^\s+$/.test(p.value) ? (conCodigo ? ' ' : '') : p.value))
      .join('')
  } catch {
    // Código de moneda inválido para Intl: monto con dos decimales y el código tal cual.
    const numero = new Intl.NumberFormat('es-GT', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(monto)
    return codigo ? `${codigo} ${numero}` : numero
  }
}
