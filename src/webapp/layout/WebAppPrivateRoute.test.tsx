import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, act } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

// Lo que se mide: la ruta privada del paciente no decide con la ficha a medio cargar. Con sesión y
// ficha, «Acceso restringido» no aparece NUNCA (ni un instante); sin ficha, sí; sin sesión, va al
// login del paciente; y si la sesión cambia mientras carga, la respuesta vieja se descarta.

type Usuario = { id: string; email: string }
let sesion: Usuario | null = null
const fichas: Record<string, { id: number; nombre: string } | null> = {}
// Respuestas de la ficha que el test libera a mano, para medir qué se ve mientras carga.
const pendientes: { uid: string; resolver: () => void }[] = []
let authListener: ((evento: string, s: { user: Usuario } | null) => void) | null = null

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: async () => ({ data: { session: sesion ? { user: sesion } : null } }),
      onAuthStateChange: (cb: typeof authListener) => {
        authListener = cb
        return { data: { subscription: { unsubscribe: () => { authListener = null } } } }
      },
      getUser: async () => ({ data: { user: sesion } }),
      signOut: async () => ({ error: null }),
    },
    from: (tabla: string) => {
      const filtros: Record<string, unknown> = {}
      const q: Record<string, unknown> = {}
      q.select = () => q
      q.eq = (col: string, val: unknown) => { filtros[col] = val; return q }
      q.maybeSingle = () => new Promise((resolve) => {
        const uid = String(filtros.auth_user_id ?? '')
        const responder = () => resolve({ data: filtros.auth_user_id ? fichas[uid] ?? null : null, error: null })
        if (filtros.auth_user_id) pendientes.push({ uid, resolver: responder })
        else responder()
      })
      // notificaciones_pacientes: select(..., { head: true }).eq().eq() es thenable con count
      q.then = (ok: (v: unknown) => unknown) => Promise.resolve({ count: tabla === 'notificaciones_pacientes' ? 0 : null }).then(ok)
      return q
    },
  },
}))

import WebAppPrivateRoute from './WebAppPrivateRoute'

function montar() {
  return render(
    <MemoryRouter initialEntries={['/paciente/dashboard']}>
      <Routes>
        <Route path="/paciente/login" element={<p>login del paciente</p>} />
        <Route path="/paciente/dashboard" element={<WebAppPrivateRoute><p>contenido del portal</p></WebAppPrivateRoute>} />
      </Routes>
    </MemoryRouter>
  )
}

async function liberar(uid: string) {
  await act(async () => {
    for (const p of pendientes.filter((x) => x.uid === uid)) p.resolver()
    await Promise.resolve()
  })
}

beforeEach(() => {
  sesion = null
  for (const k of Object.keys(fichas)) delete fichas[k]
  pendientes.length = 0
  authListener = null
})

describe('WebAppPrivateRoute — sin parpadeo de «Acceso restringido»', () => {
  it('con sesión y ficha muestra el portal sin pasar por «Acceso restringido»', async () => {
    sesion = { id: 'u-pac', email: 'pac@qa.test' }
    fichas['u-pac'] = { id: 23, nombre: 'Paciente' }
    montar()
    // La sesión ya se resolvió y la ficha todavía no: tiene que seguir el spinner.
    await waitFor(() => expect(pendientes.length).toBeGreaterThan(0))
    await act(async () => { await Promise.resolve() })
    expect(screen.queryByText('Acceso restringido')).toBeNull()
    expect(screen.queryByText('contenido del portal')).toBeNull()
    await liberar('u-pac')
    await waitFor(() => expect(screen.getByText('contenido del portal')).toBeTruthy())
    expect(screen.queryByText('Acceso restringido')).toBeNull()
  })

  it('con sesión y sin ficha muestra «Acceso restringido»', async () => {
    sesion = { id: 'u-med', email: 'med@qa.test' }
    montar()
    await waitFor(() => expect(pendientes.length).toBeGreaterThan(0))
    await liberar('u-med')
    await waitFor(() => expect(screen.getByText('Acceso restringido')).toBeTruthy())
    expect(screen.queryByText('contenido del portal')).toBeNull()
  })

  it('sin sesión redirige al login del paciente', async () => {
    montar()
    await waitFor(() => expect(screen.getByText('login del paciente')).toBeTruthy())
  })

  it('si la sesión cambia mientras carga, descarta la respuesta vieja', async () => {
    sesion = { id: 'u-pac', email: 'pac@qa.test' }
    fichas['u-pac'] = { id: 23, nombre: 'Paciente' }
    montar()
    await waitFor(() => expect(pendientes.some((p) => p.uid === 'u-pac')).toBe(true))
    // Cambia a una cuenta sin ficha antes de que vuelva la lectura de la primera.
    sesion = { id: 'u-otro', email: 'otro@qa.test' }
    await act(async () => { authListener?.('SIGNED_IN', { user: sesion! }) })
    await liberar('u-pac')
    // La ficha vieja no se aplica: sigue cargando la nueva sesión.
    expect(screen.queryByText('contenido del portal')).toBeNull()
    expect(screen.queryByText('Acceso restringido')).toBeNull()
    await liberar('u-otro')
    await waitFor(() => expect(screen.getByText('Acceso restringido')).toBeTruthy())
    expect(screen.queryByText('contenido del portal')).toBeNull()
  })
})
