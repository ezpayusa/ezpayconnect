import { describe, it, expect } from 'vitest'
import { nombreMedicoConPrefijo } from './nombreMedico'

describe('nombreMedicoConPrefijo', () => {
  it('antepone «Dr.» a un nombre sin prefijo', () => {
    expect(nombreMedicoConPrefijo('Médico QA')).toBe('Dr. Médico QA')
  })

  it('no repite el prefijo: Dr., Dra., «Dr », «Dra », sin importar mayúsculas', () => {
    for (const n of ['Dr. Juan Pérez', 'Dra. Ana López', 'Dr Juan', 'Dra Ana', 'DR. JUAN', 'dra. ana', 'Dr.Prueba']) {
      expect(nombreMedicoConPrefijo(n)).toBe(n)
    }
  })

  it('un nombre que solo empieza parecido sí lleva el prefijo', () => {
    expect(nombreMedicoConPrefijo('Draco Malfoy')).toBe('Dr. Draco Malfoy')
    expect(nombreMedicoConPrefijo('Drummond')).toBe('Dr. Drummond')
  })

  it('vacío o NULL: el texto de respaldo, sin «Dr.» suelto', () => {
    expect(nombreMedicoConPrefijo(null)).toBe('Médico')
    expect(nombreMedicoConPrefijo('  ')).toBe('Médico')
    expect(nombreMedicoConPrefijo('', '—')).toBe('—')
  })
})
