import { useMemo, useState, useEffect } from 'react'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { HeartPulse, Wind, Thermometer, Scale, Ruler, Gauge, Droplets, Loader2 } from 'lucide-react'
import { useUnidadPeso } from '@/hooks/useUnidadPeso'
import { kgAInput, inputAKg, type UnidadPeso } from '@/lib/unidades'

// Valores del formulario de vitales (strings = lo que tipea el usuario; la página los convierte a número/null).
export interface VitalesValues {
  presion_arterial: string
  frecuencia_cardiaca: string
  frecuencia_respiratoria: string
  temperatura: string
  peso_kg: string
  talla_cm: string
  saturacion_o2: string
  glucosa: string
  notas: string
}

export const VITALES_VACIO: VitalesValues = {
  presion_arterial: '', frecuencia_cardiaca: '', frecuencia_respiratoria: '',
  temperatura: '', peso_kg: '', talla_cm: '', saturacion_o2: '', glucosa: '', notas: '',
}

/**
 * Grid de inputs de signos vitales + IMC calculado en cliente. SIN acople a SOAP/consulta —
 * reutilizable (admisión Ola 2C, validación Ola 3). El IMC mostrado es informativo; el server
 * lo recalcula con el trigger trg_calcular_imc.
 */
export function FormularioVitales({ values, onChange, onSubmit, loading }: {
  values: VitalesValues
  onChange: (campo: keyof VitalesValues, valor: string) => void
  onSubmit: () => void
  loading?: boolean
}) {
  const { unidad: unidadPais, loading: cargandoUnidad } = useUnidadPeso()
  const [unidadPeso, setUnidadPeso] = useState<UnidadPeso>('kg')
  const [unidadTocada, setUnidadTocada] = useState(false)
  useEffect(() => {
    if (!cargandoUnidad && !unidadTocada) setUnidadPeso(unidadPais)
  }, [cargandoUnidad, unidadPais, unidadTocada])
  const cambiarUnidad = (u: UnidadPeso) => { setUnidadTocada(true); setUnidadPeso(u) }

  const imc = useMemo(() => {
    const peso = parseFloat(values.peso_kg)
    const talla = parseFloat(values.talla_cm)
    if (!peso || !talla) return null
    const m = talla / 100
    return (peso / (m * m)).toFixed(2)
  }, [values.peso_kg, values.talla_cm])

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit() }} className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        <div>
          <Label className="text-xs flex items-center gap-1"><HeartPulse className="h-3 w-3" /> PA (mmHg)</Label>
          <Input placeholder="120/80" value={values.presion_arterial} onChange={e => onChange('presion_arterial', e.target.value)} className="h-8 text-sm" />
        </div>
        <div>
          <Label className="text-xs flex items-center gap-1"><HeartPulse className="h-3 w-3" /> FC (lpm)</Label>
          <Input type="number" placeholder="72" value={values.frecuencia_cardiaca} onChange={e => onChange('frecuencia_cardiaca', e.target.value)} className="h-8 text-sm" />
        </div>
        <div>
          <Label className="text-xs flex items-center gap-1"><Wind className="h-3 w-3" /> FR (rpm)</Label>
          <Input type="number" placeholder="16" value={values.frecuencia_respiratoria} onChange={e => onChange('frecuencia_respiratoria', e.target.value)} className="h-8 text-sm" />
        </div>
        <div>
          <Label className="text-xs flex items-center gap-1"><Thermometer className="h-3 w-3" /> Temp (°C)</Label>
          <Input type="number" step="0.1" placeholder="36.5" value={values.temperatura} onChange={e => onChange('temperatura', e.target.value)} className="h-8 text-sm" />
        </div>
        <div>
          <div className="flex items-center justify-between">
            <Label className="text-xs flex items-center gap-1"><Scale className="h-3 w-3" /> Peso ({unidadPeso})</Label>
            <div className="flex rounded border border-slate-200 overflow-hidden text-[10px]">
              <button type="button" onClick={() => cambiarUnidad('kg')} className={unidadPeso === 'kg' ? 'px-1.5 bg-[#1E5C8E] text-white' : 'px-1.5 bg-white text-slate-500'}>kg</button>
              <button type="button" onClick={() => cambiarUnidad('lb')} className={unidadPeso === 'lb' ? 'px-1.5 bg-[#1E5C8E] text-white' : 'px-1.5 bg-white text-slate-500'}>lb</button>
            </div>
          </div>
          <Input type="number" step="0.1" placeholder={unidadPeso === 'lb' ? '154.0' : '70.0'} value={kgAInput(values.peso_kg, unidadPeso)} onChange={e => onChange('peso_kg', inputAKg(e.target.value, unidadPeso))} className="h-8 text-sm" />
        </div>
        <div>
          <Label className="text-xs flex items-center gap-1"><Ruler className="h-3 w-3" /> Talla (cm)</Label>
          <Input type="number" placeholder="170" value={values.talla_cm} onChange={e => onChange('talla_cm', e.target.value)} className="h-8 text-sm" />
        </div>
        <div>
          <Label className="text-xs flex items-center gap-1"><Gauge className="h-3 w-3" /> SpO2 (%)</Label>
          <Input type="number" placeholder="98" value={values.saturacion_o2} onChange={e => onChange('saturacion_o2', e.target.value)} className="h-8 text-sm" />
        </div>
        <div>
          <Label className="text-xs flex items-center gap-1"><Droplets className="h-3 w-3" /> Glucosa</Label>
          <Input type="number" placeholder="90" value={values.glucosa} onChange={e => onChange('glucosa', e.target.value)} className="h-8 text-sm" />
        </div>
      </div>
      <div>
        <Label className="text-xs">Notas</Label>
        <Input value={values.notas} onChange={e => onChange('notas', e.target.value)} className="h-8 text-sm" placeholder="Observaciones" />
      </div>
      {imc && (
        <div className="bg-slate-50 p-2 rounded text-center text-sm">
          <span className="text-muted-foreground">IMC: </span>
          <span className="font-bold text-[#1E5C8E]">{imc}</span>
        </div>
      )}
      <Button type="submit" disabled={loading} className="w-full bg-[#1E5C8E] hover:bg-[#164a70]">
        {loading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Guardando…</> : 'Guardar toma'}
      </Button>
    </form>
  )
}
