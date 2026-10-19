import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import BotonesNavegar from './BotonesNavegar'

const LAT = 14.6567083
const LNG = -90.4967467

describe('BotonesNavegar', () => {
  it('planificada + coordenada válida: los dos links por coordenada, en pestaña nueva, sin aviso', () => {
    render(<BotonesNavegar estado="planificada" lat={LAT} lng={LNG} direccion="X" />)
    const nav = screen.getByRole('link', { name: /navegar/i })
    expect(nav).toHaveAttribute('href',
      'https://www.google.com/maps/dir/?api=1&destination=14.6567083,-90.4967467&travelmode=driving')
    expect(nav).toHaveAttribute('target', '_blank')
    expect(nav).toHaveAttribute('rel', 'noopener noreferrer')
    const waze = screen.getByRole('link', { name: /waze/i })
    expect(waze).toHaveAttribute('href', 'https://waze.com/ul?ll=14.6567083,-90.4967467&navigate=yes')
    expect(waze).toHaveAttribute('target', '_blank')
    expect(waze).toHaveAttribute('rel', 'noopener noreferrer')
    expect(screen.queryByText(/Por dirección/)).not.toBeInTheDocument()
  })

  it('en_curso + sin coordenada + dirección: links por dirección y el aviso', () => {
    const dir = '8A Avenida 15-08, Zona 10'
    render(<BotonesNavegar estado="en_curso" lat={null} lng={null} direccion={dir} />)
    const q = encodeURIComponent(dir)
    expect(screen.getByRole('link', { name: /navegar/i }).getAttribute('href')).toContain(q)
    expect(screen.getByRole('link', { name: /waze/i }).getAttribute('href')).toContain(q)
    expect(screen.getByText('Por dirección: este prospecto no tiene ubicación cargada')).toBeInTheDocument()
  })

  for (const estado of ['realizada', 'cancelada', 'no_realizada', null, undefined]) {
    it(`estado ${String(estado)} con coordenada válida: no renderiza nada`, () => {
      const { container } = render(<BotonesNavegar estado={estado} lat={LAT} lng={LNG} direccion="X" />)
      expect(container).toBeEmptyDOMElement()
    })
  }

  it('planificada sin coordenada ni dirección: no renderiza nada', () => {
    const { container } = render(<BotonesNavegar estado="planificada" lat={null} lng={null} direccion={null} />)
    expect(container).toBeEmptyDOMElement()
  })
})
