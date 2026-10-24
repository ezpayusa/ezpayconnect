import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'

// Lo que se mide: el badge cuenta las no leídas; tocar una notificación la marca leída (solo si no lo
// estaba) y navega a su accion_url con el router; una ruta que el router no conoce cae en el comodín `*`
// (en la app, NotFoundPage), no en una pantalla en blanco.

type N = { id: string; titulo: string; mensaje: string; leida: boolean; accion_url: string | null; tipo: string; created_at: string }

let notifs: N[] = []
const marcarLeida = vi.fn(async (_id: string) => {})
const listar = vi.fn(async () => notifs)
const usos: unknown[] = []

vi.mock('@/hooks/useNotificaciones', () => ({
  useNotificaciones: (opts?: unknown) => {
    usos.push(opts)
    return {
      notificaciones: notifs,
      noLeidas: notifs.filter((n) => !n.leida).length,
      loading: false,
      listarNotificaciones: listar,
      marcarLeida,
      marcarTodasLeidas: vi.fn(),
    }
  },
}))

import NotificacionesBadge from './NotificacionesBadge'

const AHORA = new Date().toISOString()

function montar() {
  return render(
    <MemoryRouter initialEntries={['/comercial/hoy']}>
      <Routes>
        <Route path="/comercial/hoy" element={<NotificacionesBadge tono="oscuro" />} />
        <Route path="/comercial/prospectos" element={<p>destino prospectos</p>} />
        <Route path="*" element={<p>pagina no encontrada</p>} />
      </Routes>
    </MemoryRouter>,
  )
}

describe('NotificacionesBadge', () => {
  beforeEach(() => {
    marcarLeida.mockClear()
    listar.mockClear()
    usos.length = 0
    notifs = [
      { id: 'n1', titulo: 'Nuevo mensaje', mensaje: 'Ana te escribió', leida: false, accion_url: '/comercial/prospectos', tipo: 'chat_comercial', created_at: AHORA },
      { id: 'n2', titulo: 'Nuevo mensaje', mensaje: 'Luis te escribió', leida: false, accion_url: '/comercial/mensajes/abc-123', tipo: 'chat_comercial', created_at: AHORA },
      { id: 'n3', titulo: 'Aviso viejo', mensaje: 'ya leído', leida: true, accion_url: '/comercial/prospectos', tipo: 'chat_comercial', created_at: AHORA },
    ]
  })

  it('carga al montar, pide realtime y muestra el número de no leídas', () => {
    montar()
    expect(listar).toHaveBeenCalledTimes(1)
    expect(usos[0]).toEqual({ realtime: true })
    expect(screen.getByTestId('notificaciones-no-leidas').textContent).toBe('2')
  })

  it('tocar una no leída la marca leída y navega a su accion_url', async () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Notificaciones' }))
    fireEvent.click(screen.getByText('Ana te escribió'))
    await waitFor(() => expect(screen.getByText('destino prospectos')).toBeTruthy())
    expect(marcarLeida).toHaveBeenCalledWith('n1')
  })

  it('una ya leída navega sin volver a marcarla', async () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Notificaciones' }))
    fireEvent.click(screen.getByText('ya leído'))
    await waitFor(() => expect(screen.getByText('destino prospectos')).toBeTruthy())
    expect(marcarLeida).not.toHaveBeenCalled()
  })

  it('una ruta que el router no conoce cae en el comodín, no en blanco', async () => {
    montar()
    fireEvent.click(screen.getByRole('button', { name: 'Notificaciones' }))
    fireEvent.click(screen.getByText('Luis te escribió'))
    await waitFor(() => expect(screen.getByText('pagina no encontrada')).toBeTruthy())
    expect(marcarLeida).toHaveBeenCalledWith('n2')
  })
})
