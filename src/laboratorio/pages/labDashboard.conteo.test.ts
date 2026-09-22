import { describe, it, expect } from 'vitest'
import { contarExamenes } from './LabDashboard'
import { ordenCompletada } from './LabOrdenesPage'

// ############################################################################################
// El dashboard del laboratorio y su bandeja tienen que contar lo mismo
// ############################################################################################
// El bug: el dashboard hacía `ordenes.filter(o => o.estado === …)` y `OrdenAgrupada` no tiene
// `estado` — el estado vive en `items[]`. Las tres tarjetas daban 0 para siempre.
//
// Se importan las DOS funciones reales (contarExamenes del dashboard, ordenCompletada de la
// bandeja) en vez de reescribirlas acá: una copia se desincroniza y el test quedaría en verde
// mientras las pantallas divergen.
//
// SOBRE LA INVARIANTE CRUZADA, que es más sutil de lo que parece. "Pendientes + En proceso" del
// dashboard cuenta EXÁMENES; la bandeja filtra ÓRDENES. No son la misma unidad y NO dan el mismo
// número: una orden de 3 estudios todos pendientes es 1 en la bandeja y 3 en el dashboard.
// Lo que sí vale siempre, y es lo que se verifica, es:
//
//     pendientes + enProceso  ==  exámenes NO completados que viven en órdenes activas
//
// Se cumple por construcción: si un examen no está completado, su orden no puede tener
// `every(completado)`, así que la bandeja la muestra. Y al revés, las órdenes que la bandeja
// esconde tienen todos sus exámenes completados. La prueba de abajo mide las dos direcciones.

type Item = { estado: string }
type Orden = { items: Item[] }

const orden = (...estados: string[]): Orden => ({ items: estados.map((estado) => ({ estado })) })

// Los exámenes NO completados que viven en las órdenes que la bandeja muestra como activas.
const examenesActivosEnLaBandeja = (ordenes: Orden[]) =>
  ordenes
    .filter((o) => !ordenCompletada(o as any))
    .flatMap((o) => o.items)
    .filter((i) => i.estado !== 'completado').length

describe('LabDashboard — conteo por examen', () => {
  it('cuenta por ÍTEM y no por orden, con estados mezclados en la misma orden', () => {
    // Una sola orden con los 5 estados del enum adentro. Si el conteo fuera por orden, esto daría
    // 1 en algún balde y 0 en los otros dos.
    const ordenes = [orden('pendiente', 'recibida', 'en_proceso', 'revision', 'completado')]
    expect(contarExamenes(ordenes)).toEqual({ pendientes: 1, enProceso: 3, completadas: 1 })
  })

  it('`revision` cuenta como En proceso (no estaba contemplado antes)', () => {
    expect(contarExamenes([orden('revision')])).toEqual({ pendientes: 0, enProceso: 1, completadas: 0 })
  })

  it('los tres baldes PARTICIONAN el total: ningún examen se pierde', () => {
    // Si mañana `examen_estado` estrena un sexto valor, este test falla en vez de tragárselo en
    // silencio. Los 5 valores vivos son: pendiente · recibida · en_proceso · revision · completado.
    const TODOS = ['pendiente', 'recibida', 'en_proceso', 'revision', 'completado']
    const ordenes = [orden(...TODOS), orden(...TODOS), orden('pendiente')]
    const total = ordenes.reduce((n, o) => n + o.items.length, 0)
    const c = contarExamenes(ordenes)
    expect(c.pendientes + c.enProceso + c.completadas).toBe(total)
  })

  it('CRUZADO: pendientes + enProceso == exámenes no completados de las órdenes activas', () => {
    const casos: Orden[][] = [
      // orden mixta: 2 entregados y 1 en proceso
      [orden('completado', 'completado', 'en_proceso')],
      // una orden entera completada (la bandeja la esconde) + una activa
      [orden('completado', 'completado'), orden('pendiente', 'revision')],
      // varias órdenes, todos los estados repartidos
      [orden('pendiente'), orden('recibida', 'completado'), orden('revision', 'en_proceso', 'completado')],
      // borde: sin órdenes
      [],
      // borde: todo completado
      [orden('completado'), orden('completado', 'completado')],
    ]
    for (const ordenes of casos) {
      const c = contarExamenes(ordenes)
      expect(c.pendientes + c.enProceso).toBe(examenesActivosEnLaBandeja(ordenes))
    }
  })

  it('contar ÓRDENES en vez de exámenes daría otro número (por eso la unidad importa)', () => {
    // Documenta por qué el cruzado se hace contra exámenes y no contra el conteo de órdenes de la
    // bandeja: 1 orden, 3 pendientes. La bandeja muestra 1 fila; el dashboard tiene que decir 3.
    const ordenes = [orden('pendiente', 'pendiente', 'pendiente')]
    const c = contarExamenes(ordenes)
    const ordenesActivas = ordenes.filter((o) => !ordenCompletada(o as any)).length
    expect(c.pendientes + c.enProceso).toBe(3)
    expect(ordenesActivas).toBe(1)
  })

  it('REGRESIÓN: el conteo viejo (por o.estado) daba cero', () => {
    // Ancla del bug. `OrdenAgrupada` no tiene `estado`, así que el filtro comparaba contra
    // undefined. Si alguien vuelve a contar por orden, contarExamenes deja de coincidir con esto.
    const ordenes = [orden('pendiente', 'recibida'), orden('completado')]
    const viejo = (ordenes as any[]).filter((o) => o.estado === 'pendiente').length
    expect(viejo).toBe(0)
    expect(contarExamenes(ordenes).pendientes).toBe(1)
  })
})
