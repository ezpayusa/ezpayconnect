import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook } from '@testing-library/react'
import { puedeEnrolarEmpresa } from '@/visitador/lib/visibilidadEnrolamiento'

let tipo: string | undefined = 'laboratorio_farmaceutico'
let caps: string[] = ['enrolamiento']
let loadingAuth = false
let loadingCaps = false

vi.mock('@/proveedor/hooks/useProveedorAuth', () => ({
  useProveedorAuth: () => ({ loading: loadingAuth, empresa: tipo ? { tipo } : null }),
}))
vi.mock('@/proveedor/hooks/useCapacidades', () => ({
  useCapacidades: () => ({ loading: loadingCaps, tieneCapacidad: (c: string) => caps.includes(c) }),
}))

const { usePuedeEnrolar } = await import('./usePuedeEnrolar')
const gate = () => renderHook(() => usePuedeEnrolar()).result.current

beforeEach(() => {
  tipo = 'laboratorio_farmaceutico'
  caps = ['enrolamiento']
  loadingAuth = false
  loadingCaps = false
})

describe('puedeEnrolarEmpresa / usePuedeEnrolar', () => {
  it('predicado: solo laboratorio_farmaceutico con el módulo', () => {
    expect(puedeEnrolarEmpresa('laboratorio_farmaceutico', true)).toBe(true)
    expect(puedeEnrolarEmpresa('laboratorio_farmaceutico', false)).toBe(false)
    for (const t of ['farmacia', 'laboratorio_clinico', 'empresa_afin', null, undefined]) {
      expect(puedeEnrolarEmpresa(t, true)).toBe(false)
    }
  })

  it('lab farmacéutico + enrolamiento -> true', () => {
    expect(gate().puedeEnrolar).toBe(true)
  })

  it('farmacia (farmacia.qa) -> false aunque tuviera la capacidad', () => {
    tipo = 'farmacia'
    expect(gate().puedeEnrolar).toBe(false)
  })

  it("con 'visitadores' pero sin 'enrolamiento' -> false", () => {
    caps = ['visitadores']
    expect(gate().puedeEnrolar).toBe(false)
  })

  it('sin empresa o cargando -> false (deny-by-default)', () => {
    tipo = undefined
    expect(gate().puedeEnrolar).toBe(false)
    tipo = 'laboratorio_farmaceutico'
    loadingCaps = true
    expect(gate()).toEqual({ puedeEnrolar: false, loading: true })
  })
})
