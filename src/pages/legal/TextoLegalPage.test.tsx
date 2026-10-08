import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import TextoLegalPage, { MarkdownLegal } from './TextoLegalPage'
import { TEXTOS_LEGALES, type CodigoTextoLegal } from '@/legal'

// Un encabezado propio de cada texto, copiado del .md de src/legal.
const ENCABEZADO_PROPIO: Record<CodigoTextoLegal, string> = {
  terminos: '1.1 Quiénes somos y aceptación',
  privacidad: '2.1 Responsable',
  consentimiento_salud: '3.1 Qué autorizo',
  condiciones_profesionales: '4.2 Médicos',
}

describe('TextoLegalPage', () => {
  it.each(TEXTOS_LEGALES.map((t) => [t.codigo, t] as const))('%s: título, versión, encabezado propio y Volver', (codigo, t) => {
    render(
      <MemoryRouter>
        <TextoLegalPage codigo={codigo} />
      </MemoryRouter>,
    )
    expect(screen.getByRole('heading', { level: 1, name: t.titulo })).toBeInTheDocument()
    expect(screen.getByText('Versión 0.1 (provisional)')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 3, name: ENCABEZADO_PROPIO[codigo] })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Volver/ })).toHaveAttribute('href', '/')
  })

  it('las tablas del markdown quedan dentro de un contenedor con overflow-x-auto', () => {
    const { container } = render(<MarkdownLegal contenido={'| a | b |\n|---|---|\n| 1 | 2 |\n'} />)
    const tabla = container.querySelector('table')
    expect(tabla).not.toBeNull()
    expect(tabla!.parentElement).toHaveClass('overflow-x-auto')
  })

  it('el HTML crudo del markdown NO se inyecta (ni <script> ni <img onerror>)', () => {
    const malicioso = [
      '## Título',
      '',
      '<script>window.__pwned = true</script>',
      '',
      'Texto <img src="x" onerror="window.__pwned = true"> en línea.',
      '',
      '<div><img src=x onerror=alert(1)></div>',
      '',
      '[enlace](javascript:alert(1))',
    ].join('\n')
    const { container } = render(<MarkdownLegal contenido={malicioso} />)
    expect(container.querySelector('script')).toBeNull()
    expect(container.querySelector('img')).toBeNull()
    expect(container.querySelector('[onerror]')).toBeNull()
    expect(container.querySelector('a[href^="javascript:"]')).toBeNull()
    expect((window as unknown as { __pwned?: boolean }).__pwned).toBeUndefined()
    // El markdown normal sí se renderiza.
    expect(screen.getByRole('heading', { level: 2, name: 'Título' })).toBeInTheDocument()
  })
})
