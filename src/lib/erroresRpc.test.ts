import { describe, it, expect } from 'vitest'
import { mapearErrorRpc, esNoAutorizado } from './erroresRpc'

// Simula lo que devuelve supabase.rpc() en `error`.
const pg = (code: string, message = '') => ({ code, message, details: null, hint: null })

describe('mapearErrorRpc — una fila del contrato por caso', () => {
  it('42501 -> toast con texto propio, no el "no_autorizado" crudo de la base', () => {
    const r = mapearErrorRpc(pg('42501', 'no_autorizado'))
    expect(r.destino).toBe('toast')
    expect(r.mensaje).toBe('No tenés permiso para esta acción.')
    expect(r.mensaje).not.toMatch(/no_autorizado/)
    expect(r.reportar).toBe(false)
  })

  it.each(['PA001', 'PA002', 'PA003', 'PA004', 'PA005', 'PA006', 'PA007'])(
    '%s (guards de la 264) -> toast con el mensaje de la base, sin el prefijo del código',
    (code) => {
      const r = mapearErrorRpc(pg(code, `${code}: el supervisor X es de otro país`))
      expect(r.destino).toBe('toast')
      expect(r.mensaje).toBe('el supervisor X es de otro país')
      expect(r.reportar).toBe(false)
    },
  )

  it('PA008 -> inline en el selector de asesor', () => {
    const r = mapearErrorRpc(pg('PA008', 'PA008: el asesor X tiene la ficha inactiva'))
    expect(r.destino).toBe('inline')
    expect(r.campo).toBe('asesor_id')
  })

  it('PA009 -> inline en el selector de asesor', () => {
    const r = mapearErrorRpc(pg('PA009', 'PA009: X tiene rol medico'))
    expect(r.destino).toBe('inline')
    expect(r.campo).toBe('asesor_id')
    expect(r.mensaje).toBe('X tiene rol medico')
  })

  it('PA010 -> inline y además pide recargar el catálogo', () => {
    const r = mapearErrorRpc(pg('PA010', 'PA010: el tipo X esta inactivo'))
    expect(r.destino).toBe('inline')
    expect(r.recargar).toBe('catalogo')
  })

  it('PA011 (motivo faltante) -> inline en el campo motivo, NUNCA toast', () => {
    const r = mapearErrorRpc(pg('PA011', 'PA011: hace falta motivo_perdida'))
    expect(r.destino).toBe('inline')
    expect(r.campo).toBe('motivo_perdida')
  })

  it('PA012 -> toast y revertir el selector (el estado no cambió)', () => {
    const r = mapearErrorRpc(pg('PA012', 'PA012: reabrirlo es del admin de pais'))
    expect(r.destino).toBe('toast')
    expect(r.revertir).toBe(true)
  })

  it('PA013 -> toast y recargar contactos (la lista local miente)', () => {
    const r = mapearErrorRpc(pg('PA013', 'PA013: el contacto no pertenece al prospecto'))
    expect(r.recargar).toBe('contactos')
  })

  it('PA014 -> inline en el selector de país', () => {
    const r = mapearErrorRpc(pg('PA014', 'PA014: exige autoridad sobre los DOS paises'))
    expect(r.destino).toBe('inline')
    expect(r.campo).toBe('pais_id')
  })

  it('23505 -> texto propio: el de Postgres nombra el índice y no sirve para mostrar', () => {
    const r = mapearErrorRpc(pg('23505', 'duplicate key value violates unique constraint "prospectos_pais_nombrenorm_uniq"'))
    expect(r.destino).toBe('inline')
    expect(r.mensaje).toMatch(/Ya existe un registro/)
    expect(r.mensaje).not.toMatch(/constraint/)
    expect(r.recargar).toBe('visita')   // el caso típico es una pantalla vieja
  })

  it('23505 NO nombra una constraint concreta: el mismo código sale de tres UNIQUE distintos', () => {
    // Salía del nombre de prospecto duplicado, del código de asesor y del segundo informe de una
    // visita. Enumerar las dos primeras hacía que el mensaje fuera FALSO en la tercera.
    const r = mapearErrorRpc(pg('23505', 'duplicate key value violates unique constraint "reportes_visita_visita_id_key"'))
    expect(r.mensaje).not.toMatch(/nombre del prospecto/)
    expect(r.mensaje).not.toMatch(/código de asesor/)
  })

  it('23514 -> texto propio, inline', () => {
    expect(mapearErrorRpc(pg('23514', 'violates check constraint')).destino).toBe('inline')
  })

  it('428C9 (escribir una columna GENERATED) -> genérico y SÍ se reporta: es bug nuestro', () => {
    const r = mapearErrorRpc(pg('428C9', 'cannot insert a non-DEFAULT value into column "nombre_norm"'))
    expect(r.reportar).toBe(true)
    expect(r.mensaje).toMatch(/No se pudo completar/)
  })

  it('esNoAutorizado sólo con 42501', () => {
    expect(esNoAutorizado(pg('42501'))).toBe(true)
    expect(esNoAutorizado(pg('PA009'))).toBe(false)
    expect(esNoAutorizado(null)).toBe(false)
  })
})

describe('frente visitas — PA015 a PA025', () => {
  it.each(['PA015', 'PA016', 'PA017', 'PA024'])(
    '%s -> toast con el mensaje de la base, sin reportar (es del usuario, no bug nuestro)',
    (code) => {
      const r = mapearErrorRpc(pg(code, `${code}: los países no coinciden`))
      expect(r.destino).toBe('toast')
      expect(r.mensaje).toBe('los países no coinciden')
      expect(r.reportar).toBe(false)
      expect(r.sinMapear).toBeUndefined()
    },
  )

  it.each([['PA019', 'jornada'], ['PA020', 'jornada'], ['PA021', 'jornada'],
           ['PA022', 'jornada'], ['PA018', 'visita'], ['PA025', 'visita']] as const)(
    '%s deja al cliente desincronizado -> pide recargar %s',
    (code, que) => {
      expect(mapearErrorRpc(pg(code, `${code}: x`)).recargar).toBe(que)
    },
  )

  it('PA023 (path armado por el cliente) es el único del lote que SE REPORTA: el bug es nuestro', () => {
    const r = mapearErrorRpc(pg('PA023', 'PA023: el path no corresponde a la visita'))
    expect(r.reportar).toBe(true)
    // y no se le muestra al usuario el path crudo, que no significa nada para él
    expect(r.mensaje).toBe('No se pudo completar la operación. Intentá de nuevo.')
  })

  it('ninguno de los once cae en "sin mapear"', () => {
    for (const n of [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]) {
      const r = mapearErrorRpc(pg('PA0' + String(n).padStart(2, '0'), 'texto'))
      expect(r.sinMapear, 'PA0' + n + ' quedó sin mapear').toBeUndefined()
    }
  })
})

describe('los tres negativos — que el mapa envejezca bien y no rompa', () => {
  // EL IMPORTANTE. Usa el PRÓXIMO ERRCODE LIBRE, que hoy es PA026 (PA001-PA025 están tomados por
  // las migs 264/272/273/274). Este test ya se rompió una vez, al mapear PA015-PA025: es
  // exactamente lo que tiene que hacer. Cuando alguien reserve PA026, moverlo al siguiente libre
  // es parte de reservarlo.
  it('un PA0xx que NO está en el mapa NO cae en el genérico silencioso', () => {
    const r = mapearErrorRpc(pg('PA026', 'PA026: una regla que todavia no mapeamos'))
    expect(r.sinMapear).toBe(true)
    expect(r.code).toBe('PA026')
    expect(r.mensaje).toContain('PA026')          // el código queda A LA VISTA
    expect(r.mensaje).toContain('una regla que todavia no mapeamos')
    expect(r.reportar).toBe(true)                 // y llega a Sentry
    expect(r.mensaje).not.toBe('No se pudo completar la operación. Intentá de nuevo.')
  })

  it('un PA sin mapear y SIN mensaje tampoco desaparece', () => {
    const r = mapearErrorRpc(pg('PA099', ''))
    expect(r.sinMapear).toBe(true)
    expect(r.mensaje).toContain('PA099')
    expect(r.mensaje.trim()).not.toBe('')
  })

  it('error sin .code (fallo de red) -> genérico, sin romper', () => {
    for (const e of [null, undefined, new Error('Failed to fetch'), {}, 'boom', { code: '' }]) {
      const r = mapearErrorRpc(e)
      expect(r.code).toBe(null)
      expect(r.destino).toBe('toast')
      expect(r.reportar).toBe(true)
      expect(r.mensaje).toBe('No se pudo completar la operación. Intentá de nuevo.')
    }
  })

  it('.code presente pero .message vacío -> NUNCA un toast en blanco', () => {
    // Todos los códigos del mapa, con el mensaje vacío y con el campo ausente del todo.
    const codigos = ['42501', 'PA001', 'PA005', 'PA008', 'PA009', 'PA010', 'PA011',
                     'PA012', 'PA013', 'PA014', 'PA015', 'PA016', 'PA017', 'PA018',
                     'PA019', 'PA020', 'PA021', 'PA022', 'PA023', 'PA024', 'PA025',
                     '23505', '23514', '428C9', 'XX000']
    for (const code of codigos) {
      for (const err of [pg(code, ''), pg(code, '   '), { code }]) {
        const r = mapearErrorRpc(err)
        expect(r.mensaje.trim(), `código ${code} rindió un mensaje vacío`).not.toBe('')
      }
    }
  })

  it('un código desconocido que NO es PA sí va al genérico (no se inventa nada)', () => {
    const r = mapearErrorRpc(pg('40001', 'serialization failure'))
    expect(r.sinMapear).toBeUndefined()
    expect(r.mensaje).toBe('No se pudo completar la operación. Intentá de nuevo.')
    expect(r.reportar).toBe(true)
  })
})
