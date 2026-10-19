import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, act } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

const m = vi.hoisted(() => ({
  getUser: vi.fn(),
  signInWithPassword: vi.fn(),
  updateUser: vi.fn(),
  toastSuccess: vi.fn(),
}))

vi.mock('@/lib/supabase', () => ({
  supabase: { auth: { getUser: m.getUser, signInWithPassword: m.signInWithPassword, updateUser: m.updateUser } },
}))
vi.mock('sonner', () => ({ toast: { success: m.toastSuccess, error: vi.fn() } }))

import CambiarClavePage from './CambiarClavePage'

const EMAIL = 'medico.qa@ezpayqa.test'

function montar() {
  return render(
    <MemoryRouter initialEntries={['/cambiar-clave']}>
      <Routes>
        <Route path="/cambiar-clave" element={<CambiarClavePage />} />
        <Route path="/login" element={<div>PANTALLA LOGIN</div>} />
        <Route path="/" element={<div>PANTALLA RAIZ</div>} />
      </Routes>
    </MemoryRouter>,
  )
}

async function llenarYEnviar(actual: string, nueva: string, repetir: string) {
  fireEvent.change(await screen.findByLabelText('Clave actual'), { target: { value: actual } })
  fireEvent.change(screen.getByLabelText('Clave nueva'), { target: { value: nueva } })
  fireEvent.change(screen.getByLabelText('Repetir clave nueva'), { target: { value: repetir } })
  await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Guardar clave' })) })
}

beforeEach(() => {
  vi.clearAllMocks()
  m.getUser.mockResolvedValue({ data: { user: { id: 'u1', email: EMAIL } }, error: null })
  m.signInWithPassword.mockResolvedValue({ data: {}, error: null })
  m.updateUser.mockResolvedValue({ data: {}, error: null })
})

describe('CambiarClavePage', () => {
  it('sin sesión redirige a /login', async () => {
    m.getUser.mockResolvedValue({ data: { user: null }, error: null })
    montar()
    expect(await screen.findByText('PANTALLA LOGIN')).toBeInTheDocument()
  })

  it.each([
    ['clave nueva corta', 'actual-123', 'corta12', 'corta12', 'La clave nueva tiene que tener al menos 8 caracteres.'],
    ['las nuevas no coinciden', 'actual-123', 'nueva-1234', 'nueva-9999', 'Las claves nuevas no coinciden.'],
    ['nueva igual a la actual', 'misma-1234', 'misma-1234', 'misma-1234', 'La clave nueva tiene que ser distinta de la actual.'],
  ])('%s: muestra el texto y no llama a Supabase', async (_caso, actual, nueva, repetir, texto) => {
    montar()
    await llenarYEnviar(actual, nueva, repetir)
    expect(await screen.findByRole('alert')).toHaveTextContent(texto)
    expect(m.signInWithPassword).not.toHaveBeenCalled()
    expect(m.updateUser).not.toHaveBeenCalled()
  })

  it('clave actual incorrecta: muestra el texto y NO llama a updateUser', async () => {
    m.signInWithPassword.mockResolvedValue({ data: {}, error: { code: 'invalid_credentials', message: 'Invalid login credentials' } })
    montar()
    await llenarYEnviar('equivocada', 'nueva-1234', 'nueva-1234')
    expect(await screen.findByRole('alert')).toHaveTextContent('La clave actual no es correcta.')
    expect(m.signInWithPassword).toHaveBeenCalledTimes(1)
    expect(m.updateUser).not.toHaveBeenCalled()
  })

  it('feliz: verifica la actual con el email de la sesión, DESPUÉS cambia la clave y vuelve a la raíz', async () => {
    montar()
    await llenarYEnviar('actual-123', 'nueva-1234', 'nueva-1234')
    expect(await screen.findByText('PANTALLA RAIZ')).toBeInTheDocument()
    expect(m.signInWithPassword).toHaveBeenCalledWith({ email: EMAIL, password: 'actual-123' })
    expect(m.updateUser).toHaveBeenCalledWith({ password: 'nueva-1234' })
    expect(m.signInWithPassword.mock.invocationCallOrder[0]).toBeLessThan(m.updateUser.mock.invocationCallOrder[0])
    expect(m.toastSuccess).toHaveBeenCalledWith('Clave actualizada')
  })

  it('updateUser con same_password: muestra el texto de "distinta de la actual"', async () => {
    m.updateUser.mockResolvedValue({ data: {}, error: { code: 'same_password', message: 'New password should be different from the old password.' } })
    montar()
    await llenarYEnviar('actual-123', 'nueva-1234', 'nueva-1234')
    expect(await screen.findByRole('alert')).toHaveTextContent('La clave nueva tiene que ser distinta de la actual.')
    expect(m.toastSuccess).not.toHaveBeenCalled()
  })
})
