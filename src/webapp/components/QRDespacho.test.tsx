import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import QRDespacho from './QRDespacho'
import type { RecetaPaciente } from '@/webapp/types/webapp.types'

// Mig 396: el token llega por mis_despachos_receta (solo vigentes). Lo que se fija acá es qué pinta el QR en cada caso.
const TOKEN = 'b'.repeat(64)
const futuro = new Date(Date.now() + 86_400_000).toISOString()
const pasado = new Date(Date.now() - 86_400_000).toISOString()

const receta = (despacho: RecetaPaciente['despacho']): RecetaPaciente => ({
  id: 8927, medico_nombre: 'Dr. QA', estado: 'activa', instrucciones_generales: null, created_at: '2026-11-19T20:36:47Z',
  items: [{ id: 1, nombre_medicamento: 'Paracetamol', dosis: '500 mg', frecuencia: 'c/8h', duracion: null, instrucciones: null,
            cantidad: 1, farmacia_id: 5, modalidad: null, dispensado: false } as any],
  despacho,
})

describe('QRDespacho (mig 396)', () => {
  it('vigente con token de la RPC: dibuja el QR', () => {
    const { container } = render(<QRDespacho receta={receta({ token: TOKEN, expira_at: futuro, estado_dispensacion: 'pendiente' })} />)
    expect(container.querySelector('svg')).not.toBeNull()
    expect(screen.getByText(/Muestra este código en la farmacia/)).toBeInTheDocument()
    expect(container.textContent).not.toContain(TOKEN)
  })

  it('vigente pero sin token (la RPC no respondió): aviso, sin QR', () => {
    const { container } = render(<QRDespacho receta={receta({ token: null, expira_at: futuro, estado_dispensacion: 'pendiente' })} />)
    expect(screen.getByText(/No se pudo cargar el código de despacho/)).toBeInTheDocument()
    expect(container.querySelector('svg[aria-hidden="true"][height="200"]')).toBeNull()
  })

  it('vencido (la RPC no lo devuelve): aviso de vencimiento, no el de error', () => {
    render(<QRDespacho receta={receta({ token: null, expira_at: pasado, estado_dispensacion: 'pendiente' })} />)
    expect(screen.getByText(/El código de despacho venció/)).toBeInTheDocument()
    expect(screen.queryByText(/No se pudo cargar/)).toBeNull()
  })

  it('sin fila avanzada: «Receta sin código de despacho»', () => {
    render(<QRDespacho receta={receta(null)} />)
    expect(screen.getByText('Receta sin código de despacho.')).toBeInTheDocument()
  })
})
