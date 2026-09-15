import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent, within } from '@testing-library/react'
import { ConfirmarLiberacionDialog } from './ConfirmarLiberacionDialog'

// Lo que se mide: la confirmación NOMBRA cada examen y dice cuántos son. Liberar varios resultados de
// un clic sin ver cuáles fue lo que pasó en prod el 15-sep (250 y 254 liberados de golpe).

const LISTOS = [
  { id: 250, tipo: 'Hemograma', fecha_resultado: '2026-09-15' },
  { id: 254, tipo: 'orina', fecha_resultado: '2026-09-15' },
]

describe('ConfirmarLiberacionDialog', () => {
  it('nombra cada examen, con su fecha, y dice cuántos va a liberar', () => {
    render(<ConfirmarLiberacionDialog examenes={LISTOS} liberando={false} onConfirmar={() => {}} onCancelar={() => {}} />)
    expect(screen.getByRole('alertdialog')).toHaveTextContent('¿Liberar estos 2 resultados al paciente?')
    const lista = screen.getByRole('list', { name: 'Exámenes a liberar' })
    const items = within(lista).getAllByRole('listitem')
    expect(items).toHaveLength(2)
    expect(items[0]).toHaveTextContent('Hemograma')
    expect(items[1]).toHaveTextContent('orina')
    expect(items[1]).toHaveTextContent('Resultado: 2026-09-15')
    expect(screen.getByRole('button', { name: 'Liberar los 2' })).toBeInTheDocument()
  })

  it('confirmar llama a onConfirmar; cancelar NO libera nada', () => {
    const onConfirmar = vi.fn()
    const onCancelar = vi.fn()
    render(<ConfirmarLiberacionDialog examenes={LISTOS} liberando={false} onConfirmar={onConfirmar} onCancelar={onCancelar} />)
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(onConfirmar).not.toHaveBeenCalled()
    expect(onCancelar).toHaveBeenCalled()
  })

  it('el botón de confirmar dispara onConfirmar', () => {
    const onConfirmar = vi.fn()
    render(<ConfirmarLiberacionDialog examenes={LISTOS} liberando={false} onConfirmar={onConfirmar} onCancelar={() => {}} />)
    fireEvent.click(screen.getByRole('button', { name: 'Liberar los 2' }))
    expect(onConfirmar).toHaveBeenCalledTimes(1)
  })

  it('mientras libera, no se puede confirmar dos veces ni cancelar a mitad', () => {
    render(<ConfirmarLiberacionDialog examenes={LISTOS} liberando={true} onConfirmar={() => {}} onCancelar={() => {}} />)
    expect(screen.getByRole('button', { name: 'Liberando…' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled()
  })

  it('cerrado cuando no hay lista', () => {
    render(<ConfirmarLiberacionDialog examenes={null} liberando={false} onConfirmar={() => {}} onCancelar={() => {}} />)
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
  })
})
