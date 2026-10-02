import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import ResumenUltimaVisitaMedico from './ResumenUltimaVisitaMedico'

// Lo que se mide: la regla de ROL que comparten ConsultaPage y PacienteDetallePage. Sólo medico ve el
// resumen; el resto daría siempre 403 no_pertenencia (mig 340). Mientras el perfil carga, nada.
// El hijo se reemplaza por un stub: acá no importa qué hace, sólo si se monta.

let auth: { loading: boolean; rol: string | null } = { loading: false, rol: 'medico' }

vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({
    loading: auth.loading,
    perfil: auth.rol ? { rol: auth.rol } : null,
    isMedico: () => auth.rol === 'medico',
  }),
}))

vi.mock('./ResumenUltimaVisita', () => ({
  default: ({ pacienteId }: { pacienteId: number }) => <div data-testid="resumen">resumen {pacienteId}</div>,
}))

beforeEach(() => {
  auth = { loading: false, rol: 'medico' }
})

describe('ResumenUltimaVisitaMedico', () => {
  it('medico: monta el resumen con el pacienteId y el contenedor', () => {
    auth = { loading: false, rol: 'medico' }
    const { container } = render(<ResumenUltimaVisitaMedico pacienteId={23} className="mb-6" />)
    expect(screen.getByTestId('resumen')).toHaveTextContent('resumen 23')
    expect(container.firstElementChild).toHaveClass('mb-6')
  })

  it.each(['admin_clinica', 'asistente_medico', 'enfermeria', 'super_admin', 'secretaria', 'paciente'])(
    '%s: no renderiza nada (ni el contenedor)',
    (rol) => {
      auth = { loading: false, rol }
      const { container } = render(<ResumenUltimaVisitaMedico pacienteId={23} className="mb-6" />)
      expect(screen.queryByTestId('resumen')).toBeNull()
      expect(container).toBeEmptyDOMElement()
    },
  )

  it('sin perfil: no renderiza nada', () => {
    auth = { loading: false, rol: null }
    const { container } = render(<ResumenUltimaVisitaMedico pacienteId={23} />)
    expect(container).toBeEmptyDOMElement()
  })

  it('mientras carga no renderiza, y aparece cuando el perfil resulta medico (sin parpadeo)', () => {
    auth = { loading: true, rol: null }
    const { container, rerender } = render(<ResumenUltimaVisitaMedico pacienteId={23} />)
    expect(container).toBeEmptyDOMElement()
    auth = { loading: false, rol: 'medico' }
    rerender(<ResumenUltimaVisitaMedico pacienteId={23} />)
    expect(screen.getByTestId('resumen')).toBeInTheDocument()
  })

  it('mientras carga no renderiza, y sigue sin renderizar si el perfil resulta admin_clinica', () => {
    auth = { loading: true, rol: null }
    const { container, rerender } = render(<ResumenUltimaVisitaMedico pacienteId={23} />)
    expect(container).toBeEmptyDOMElement()
    auth = { loading: false, rol: 'admin_clinica' }
    rerender(<ResumenUltimaVisitaMedico pacienteId={23} />)
    expect(container).toBeEmptyDOMElement()
  })
})
