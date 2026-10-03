import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import ListaMedicosAgendar from './ListaMedicosAgendar'

// Bug del Preview del PR #29: en /visitador/agendar la tarjeta del médico salía con el ícono y el botón pero sin
// texto. La RPC devolvía nombre y especialidad; el texto quedaba en ~0 px de ancho: la lista iba en 2 columnas
// (md:grid-cols-2) dentro del PWA de max-w-md (448 px), y en la tarjeta (~200 px) el ícono y el botón
// "Seleccionar" (flex-shrink-0) se llevaban todo el espacio; el bloque de texto (min-w-0, sin flex-1) se encogía a
// 0 y truncate lo ocultaba. jsdom no calcula layout: se fijan las condiciones estructurales que lo evitan.

const medico = { id: '09d243d5-b222-482a-9762-94a582e9e752', nombre_completo: 'Dr. Médico QA', especialidad: 'Medicina General' }

describe('ListaMedicosAgendar', () => {
  it('muestra el nombre y, debajo, la especialidad del MedicoResumen de buscar_medicos_proveedor', () => {
    render(<ListaMedicosAgendar medicos={[medico]} onSeleccionar={() => {}} />)
    expect(screen.getByText('Dr. Médico QA')).toBeTruthy()
    expect(screen.getByText('Medicina General')).toBeTruthy()
    expect(screen.queryByText(/@/)).toBeNull()   // sin email
  })
  it('sin especialidad muestra "Especialidad no indicada"', () => {
    render(<ListaMedicosAgendar medicos={[{ ...medico, especialidad: null }]} onSeleccionar={() => {}} />)
    expect(screen.getByText('Especialidad no indicada')).toBeTruthy()
  })
  it('una sola columna (el PWA mide max-w-md: dos columnas dejan la tarjeta en ~200 px)', () => {
    render(<ListaMedicosAgendar medicos={[medico]} onSeleccionar={() => {}} />)
    expect(screen.getByTestId('lista-medicos').className).not.toMatch(/grid-cols-2/)
  })
  it('el texto ocupa el espacio libre (flex-1 en su bloque y en el contenedor) y el nombre no se trunca a nada', () => {
    render(<ListaMedicosAgendar medicos={[medico]} onSeleccionar={() => {}} />)
    expect(screen.getByTestId('medico-izq').className).toMatch(/\bflex-1\b/)
    expect(screen.getByTestId('medico-texto').className).toMatch(/\bflex-1\b/)
    expect(screen.getByText('Dr. Médico QA').className).not.toMatch(/\btruncate\b/)
  })
  it('seleccionar por la tarjeta o por el boton llama con el id', () => {
    const onSel = vi.fn()
    render(<ListaMedicosAgendar medicos={[medico]} onSeleccionar={onSel} />)
    fireEvent.click(screen.getByText('Seleccionar'))
    expect(onSel).toHaveBeenCalledWith(medico.id)
  })
})
