import { describe, it, expect } from 'vitest'
import { generarPDF } from './pdfReceta'

// H13: el PDF de la receta sin «N/A», con la tabla dentro del margen y «Cant.» entero.
const receta = { id: 8927, folio: 'QA-12345-000013-20261119', created_at: '2026-11-19T20:36:47Z', instrucciones_generales: null } as any
const paciente = { id: 23, nombre: 'Paciente', apellido: 'QA', telefono: null, email: null, fecha_nacimiento: null, genero: null, alergias: 'Penicilina, sulfas', emergencia_nombre: null } as any
const medico = { nombre_completo: 'Médico QA', email: '', telefono: '' } as any
const items = [{
  nombre_medicamento: 'Sulfametoxazol + Trimetoprima', dosis: '800/160 mg', frecuencia: 'Cada 12 horas',
  duracion: '7 días', cantidad: 14, instrucciones: 'Tomar con abundante agua', farmacia: null, farmacia_id: null,
  precio_unitario: null,
}] as any

describe('generarPDF (H13)', () => {
  const doc = generarPDF(receta, items, paciente, medico, 'QA-12345')
  const tabla = (doc as any).lastAutoTable

  it('los datos que faltan no se imprimen como «N/A»', () => {
    expect(doc.output()).not.toContain('N/A')
  })

  it('la tabla queda dentro del margen (180 mm de ancho útil desde x = 15)', () => {
    const ancho = tabla.columns.reduce((s: number, c: any) => s + c.width, 0)
    expect(ancho).toBeLessThanOrEqual(180.01)
    expect(tabla.settings.margin.left).toBe(15)
  })

  it('la columna «Cant.» alcanza para el encabezado en una línea', () => {
    const cant = tabla.columns[5]
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8)
    const anchoTexto = doc.getTextWidth('Cant.')
    expect(cant.width).toBeGreaterThanOrEqual(anchoTexto + 4) // + padding de 2 mm a cada lado
    expect(tabla.head[0].cells[5].text).toEqual(['Cant.'])
  })
})
