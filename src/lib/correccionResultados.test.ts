import { describe, it, expect, vi } from 'vitest'

vi.mock('@/lib/supabase', () => ({ supabase: {} }))

const {
  validarCorreccion, mensajeErrorCorreccion, leerResultadoCorreccion, revisionesPorExamen, MOTIVO_MAX,
} = await import('./correccionResultados')

const vigente = { resultados: 'Glucosa 90 mg/dL', archivo_url: 'lab/1-1.pdf' }

describe('validarCorreccion', () => {
  it('motivo vacío o solo espacios', () => {
    expect(validarCorreccion({ motivo: '   ', resultados: 'x', hayArchivoNuevo: false }, vigente)).toMatch(/obligatorio/)
  })

  it(`motivo de más de ${MOTIVO_MAX}`, () => {
    expect(validarCorreccion({ motivo: 'a'.repeat(MOTIVO_MAX + 1), resultados: 'x', hayArchivoNuevo: false }, vigente)).toMatch(/500/)
  })

  it('sin cambios: mismo texto con espacios, tabs o saltos distintos (EX028 normaliza igual)', () => {
    expect(validarCorreccion({ motivo: 'm', resultados: ' \tGlucosa 90 mg/dL\r\n', hayArchivoNuevo: false }, vigente)).toMatch(/no cambia/)
  })

  it('archivo nuevo con el mismo texto sí es un cambio', () => {
    expect(validarCorreccion({ motivo: 'm', resultados: 'Glucosa 90 mg/dL', hayArchivoNuevo: true }, vigente)).toBeNull()
  })

  it('vacío: sin texto, sin archivo nuevo y sin archivo vigente (EX034)', () => {
    expect(validarCorreccion({ motivo: 'm', resultados: ' ', hayArchivoNuevo: false }, { resultados: 'x', archivo_url: null })).toMatch(/vacío/)
  })

  it('texto distinto pasa', () => {
    expect(validarCorreccion({ motivo: 'Error de transcripción', resultados: 'Glucosa 95 mg/dL', hayArchivoNuevo: false }, vigente)).toBeNull()
  })
})

describe('mensajeErrorCorreccion', () => {
  it('EX0xx se muestra tal cual', () => {
    expect(mensajeErrorCorreccion({ code: 'EX028', message: 'La corrección no cambia el resultado' })).toBe('La corrección no cambia el resultado')
  })
  it('42501 no muestra el mensaje crudo de la base', () => {
    expect(mensajeErrorCorreccion({ code: '42501', message: 'no_autorizado' })).not.toMatch(/no_autorizado/)
  })
  it('otros códigos llevan prefijo', () => {
    expect(mensajeErrorCorreccion({ code: 'XX000', message: 'boom' })).toBe('No se pudo corregir el resultado: boom')
  })
})

describe('leerResultadoCorreccion', () => {
  it('lee el retorno de la RPC', () => {
    expect(leerResultadoCorreccion({ examen_id: 250, revision: 2, notificado: true })).toEqual({ examen_id: 250, revision: 2, notificado: true })
  })
  it('forma inesperada → null', () => {
    expect(leerResultadoCorreccion(null)).toBeNull()
    expect(leerResultadoCorreccion({ examen_id: '250' })).toBeNull()
  })
})

describe('revisionesPorExamen', () => {
  it('agrupa por examen y ordena de la más nueva a la más vieja', () => {
    const base = { resultados_anterior: null, archivo_url_anterior: null, fecha_resultado_anterior: null, liberado_al_corregir: false, motivo: 'm', corregido_at: '2026-09-26T00:00:00Z' }
    const m = revisionesPorExamen([
      { ...base, id: 1, examen_id: 250, revision: 1 },
      { ...base, id: 3, examen_id: 251, revision: 1 },
      { ...base, id: 2, examen_id: 250, revision: 2 },
    ])
    expect(m.get(250)?.map((r) => r.revision)).toEqual([2, 1])
    expect(m.get(251)?.length).toBe(1)
    expect(m.has(252)).toBe(false)
  })
})
