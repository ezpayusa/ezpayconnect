import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import IndicadorPrioridad from './IndicadorPrioridad'
import type { PrioridadAgendar } from '@/visitador/lib/enrolamiento'

const P = (p: Partial<PrioridadAgendar>): PrioridadAgendar =>
  ({ estado: 'libre', fecha_minima: null, visitas_completadas: null, visitas_limite: null, ...p })
const montar = (prioridad: PrioridadAgendar | null, puedeEnrolar = true, onEnrolar = vi.fn()) =>
  render(<IndicadorPrioridad prioridad={prioridad} puedeEnrolar={puedeEnrolar} enrolando={false} onEnrolar={onEnrolar} />)

describe('IndicadorPrioridad — los 3 estados', () => {
  it("'propia': aviso con X de Y visitas, sin botón", () => {
    montar(P({ estado: 'propia', visitas_completadas: 5, visitas_limite: 8 }))
    expect(screen.getByTestId('prioridad-propia')).toHaveTextContent('Tienes prioridad con este médico (5 de 8 visitas)')
    expect(screen.queryByRole('button')).toBeNull()
  })

  it("'otro_laboratorio': aviso con la fecha, sin botón aunque pueda enrolar", () => {
    montar(P({ estado: 'otro_laboratorio', fecha_minima: '2026-11-03' }))
    expect(screen.getByTestId('prioridad-otro'))
      .toHaveTextContent('Este médico tiene prioridad de otro laboratorio. Puedes agendar desde 03/11/2026')
    expect(screen.queryByRole('button')).toBeNull()
  })

  it("'libre' con el gate: sin aviso, botón Enrolar médico", () => {
    const onEnrolar = vi.fn()
    montar(P({ estado: 'libre' }), true, onEnrolar)
    expect(screen.queryByTestId('prioridad-propia')).toBeNull()
    expect(screen.queryByTestId('prioridad-otro')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Enrolar médico' }))
    expect(onEnrolar).toHaveBeenCalledTimes(1)
  })

  it("'libre' sin el gate: nada", () => {
    const { container } = montar(P({ estado: 'libre' }), false)
    expect(container).toBeEmptyDOMElement()
  })

  it('sin prioridad (error o cargando): nada', () => {
    const { container } = montar(null)
    expect(container).toBeEmptyDOMElement()
  })
})
