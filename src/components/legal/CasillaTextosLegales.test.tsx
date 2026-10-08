import { useState } from 'react'
import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { CasillaTextosLegales, textosPara, DECLARACION_MAYORIA_EDAD } from './CasillaTextosLegales'
import { textoLegalPorCodigo } from '@/legal'

const tituloDe = (codigo: string) => textoLegalPorCodigo(codigo)!.titulo

describe('textosPara', () => {
  it('paciente → terminos, privacidad, consentimiento_salud', () => {
    expect(textosPara('paciente').map((t) => t.codigo)).toEqual(['terminos', 'privacidad', 'consentimiento_salud'])
  })

  it('profesional → terminos, privacidad, condiciones_profesionales', () => {
    expect(textosPara('profesional').map((t) => t.codigo)).toEqual(['terminos', 'privacidad', 'condiciones_profesionales'])
  })
})

describe('CasillaTextosLegales', () => {
  it('paciente: 3 links en otra pestaña, la declaración de mayoría de edad y nada de condiciones profesionales', () => {
    render(<CasillaTextosLegales para="paciente" checked={false} onChange={() => {}} />)
    const links = screen.getAllByRole('link')
    expect(links).toHaveLength(3)
    for (const t of textosPara('paciente')) {
      const a = screen.getByRole('link', { name: new RegExp(t.titulo) })
      expect(a).toHaveAttribute('href', t.ruta)
      expect(a).toHaveAttribute('target', '_blank')
      expect(a).toHaveAttribute('rel', 'noopener noreferrer')
    }
    expect(screen.getByText(new RegExp(DECLARACION_MAYORIA_EDAD.replace(/[.]/g, '\\.')))).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: new RegExp(tituloDe('condiciones_profesionales')) })).toBeNull()
    expect(screen.queryByText(new RegExp(tituloDe('condiciones_profesionales')))).toBeNull()
  })

  it('profesional: 3 links, sin la declaración de menores ni el consentimiento de salud', () => {
    render(<CasillaTextosLegales para="profesional" checked={false} onChange={() => {}} />)
    expect(screen.getAllByRole('link')).toHaveLength(3)
    expect(screen.getByRole('link', { name: new RegExp(tituloDe('condiciones_profesionales')) })).toHaveAttribute(
      'href',
      '/condiciones-profesionales',
    )
    expect(screen.queryByText(/mayor de 18 años/)).toBeNull()
    expect(screen.queryByRole('link', { name: new RegExp(tituloDe('consentimiento_salud')) })).toBeNull()
    expect(screen.queryByText(new RegExp(tituloDe('consentimiento_salud')))).toBeNull()
  })

  it('click en el checkbox o en el label → onChange(true)', () => {
    const onChange = vi.fn()
    const { container } = render(<CasillaTextosLegales para="paciente" checked={false} onChange={onChange} id="casilla" />)
    fireEvent.click(screen.getByRole('checkbox'))
    expect(onChange).toHaveBeenLastCalledWith(true)
    fireEvent.click(container.querySelector('label[for="casilla"]')!)
    expect(onChange).toHaveBeenCalledTimes(2)
    expect(onChange).toHaveBeenLastCalledWith(true)
  })

  it('con checked=true, click → onChange(false)', () => {
    const onChange = vi.fn()
    render(<CasillaTextosLegales para="profesional" checked onChange={onChange} />)
    fireEvent.click(screen.getByRole('checkbox'))
    expect(onChange).toHaveBeenCalledWith(false)
  })

  it('con disabled no llama a onChange', () => {
    const onChange = vi.fn()
    const { container } = render(<CasillaTextosLegales para="paciente" checked={false} onChange={onChange} disabled id="c" />)
    fireEvent.click(screen.getByRole('checkbox'))
    fireEvent.click(container.querySelector('label[for="c"]')!)
    expect(onChange).not.toHaveBeenCalled()
    expect(screen.getByRole('checkbox')).toBeDisabled()
  })

  it('patrón de las altas: el submit queda deshabilitado mientras la casilla no está marcada', () => {
    const onSubmit = vi.fn()
    function FormPrueba() {
      const [acepto, setAcepto] = useState(false)
      return (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            onSubmit()
          }}
        >
          <CasillaTextosLegales para="paciente" checked={acepto} onChange={setAcepto} />
          <button type="submit" disabled={!acepto}>
            Crear cuenta
          </button>
        </form>
      )
    }
    render(<FormPrueba />)
    const boton = screen.getByRole('button', { name: 'Crear cuenta' })
    expect(boton).toBeDisabled()
    fireEvent.click(boton)
    expect(onSubmit).not.toHaveBeenCalled()

    fireEvent.click(screen.getByRole('checkbox'))
    expect(boton).toBeEnabled()
    fireEvent.click(boton)
    expect(onSubmit).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByRole('checkbox'))
    expect(boton).toBeDisabled()
  })
})
