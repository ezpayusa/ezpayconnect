import { useMemo, useState, useEffect, type ReactNode } from 'react'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { HeartPulse, Wind, Thermometer, Scale, Ruler, Gauge, Droplets, Loader2 } from 'lucide-react'
import { useUnidadPeso } from '@/hooks/useUnidadPeso'
import { kgAInput, inputAKg, type UnidadPeso } from '@/lib/unidades'
import {
  RANGOS_VITALES, PRESION_ARTERIAL, rangoPesoEnUnidad, validarVitales, campoDeErrorVital,
  type CampoVitalNumerico, type CampoConError, type ErroresVitales,
} from '@/lib/vitalesRangos'

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

function ErrorCampo({ msg }: { msg?: string }) {
  return msg ? <p role="alert" className="text-[10px] leading-tight text-red-600 mt-0.5">{msg}</p> : null
}

/**
 * Grid de inputs de signos vitales + IMC calculado en cliente. SIN acople a SOAP/consulta —
 * reutilizable (admisión Ola 2C, validación Ola 3). El IMC mostrado es informativo; el server
 * lo recalcula con el trigger trg_calcular_imc.
 * Rangos y unidades: src/lib/vitalesRangos.ts (espejo de la mig 330). Se valida en el cliente antes de
 * llamar a onSubmit; si igual la RPC rechaza con SV001/SV002, la página pasa error.message en
 * `errorServidor` y se muestra en el campo que nombra (o arriba del botón si no nombra ninguno).
 */
export function FormularioVitales({ values, onChange, onSubmit, loading, errorServidor }: {
  values: VitalesValues
  onChange: (campo: keyof VitalesValues, valor: string) => void
  onSubmit: () => void
  loading?: boolean
  errorServidor?: string | null
}) {
  const { unidad: unidadPais, loading: cargandoUnidad } = useUnidadPeso()
  const [unidadPeso, setUnidadPeso] = useState<UnidadPeso>('kg')
  const [unidadTocada, setUnidadTocada] = useState(false)
  useEffect(() => {
    if (!cargandoUnidad && !unidadTocada) setUnidadPeso(unidadPais)
  }, [cargandoUnidad, unidadPais, unidadTocada])
  const cambiarUnidad = (u: UnidadPeso) => { setUnidadTocada(true); setUnidadPeso(u) }
  const rangoPeso = rangoPesoEnUnidad(unidadPeso)

  // Buffer local del input de peso: muestra lo que el usuario tipea (sin re-derivar del kg en cada tecla).
  // Se re-sincroniza desde el kg canónico solo cuando cambia por fuera (reset/carga) o cambia la unidad.
  const [pesoBuf, setPesoBuf] = useState('')
  useEffect(() => {
    if (inputAKg(pesoBuf, unidadPeso) !== (values.peso_kg || '')) {
      setPesoBuf(kgAInput(values.peso_kg, unidadPeso))
    }
  }, [values.peso_kg, unidadPeso, pesoBuf])

  const [errores, setErrores] = useState<ErroresVitales>({})
  const [errorGeneral, setErrorGeneral] = useState<string | null>(null)
  useEffect(() => {
    if (!errorServidor) return
    const campo = campoDeErrorVital(errorServidor)
    if (campo) { setErrores({ [campo]: errorServidor }); setErrorGeneral(null) }
    else { setErrores({}); setErrorGeneral(errorServidor) }
  }, [errorServidor])

  // Al editar un campo se limpia su error (y el de la combinación si es peso o talla).
  const cambiar = (campo: keyof VitalesValues, valor: string) => {
    setErrores((e) => {
      const sig: ErroresVitales = { ...e }
      delete sig[campo as CampoConError]
      if (campo === 'peso_kg' || campo === 'talla_cm') delete sig.imc
      return sig
    })
    setErrorGeneral(null)
    onChange(campo, valor)
  }

  const enviar = () => {
    const errs = validarVitales(values)
    setErrores(errs)
    setErrorGeneral(null)
    if (Object.keys(errs).length > 0) return
    onSubmit()
  }

  const imc = useMemo(() => {
    const peso = parseFloat(values.peso_kg)
    const talla = parseFloat(values.talla_cm)
    if (!peso || !talla) return null
    const m = talla / 100
    return (peso / (m * m)).toFixed(2)
  }, [values.peso_kg, values.talla_cm])

  const numerico = (campo: Exclude<CampoVitalNumerico, 'peso_kg'>, etiqueta: string, icono: ReactNode, placeholder: string) => {
    const r = RANGOS_VITALES[campo]
    return (
      <div>
        <Label htmlFor={`vital-${campo}`} className="text-xs flex items-center gap-1">{icono} {etiqueta} ({r.unidad})</Label>
        <Input id={`vital-${campo}`} type="number" inputMode={r.entero ? 'numeric' : 'decimal'}
          min={r.min} max={r.max} step={r.step} placeholder={placeholder}
          value={values[campo]} onChange={e => cambiar(campo, e.target.value)}
          aria-invalid={!!errores[campo]}
          className={`h-8 text-sm ${errores[campo] ? 'border-red-500' : ''}`} />
        <ErrorCampo msg={errores[campo]} />
      </div>
    )
  }

  return (
    <form onSubmit={(e) => { e.preventDefault(); enviar() }} noValidate className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        <div>
          <Label htmlFor="vital-presion_arterial" className="text-xs flex items-center gap-1"><HeartPulse className="h-3 w-3" /> PA ({PRESION_ARTERIAL.unidad})</Label>
          <Input id="vital-presion_arterial" placeholder="120/80" value={values.presion_arterial}
            onChange={e => cambiar('presion_arterial', e.target.value)}
            aria-invalid={!!errores.presion_arterial}
            className={`h-8 text-sm ${errores.presion_arterial ? 'border-red-500' : ''}`} />
          <ErrorCampo msg={errores.presion_arterial} />
        </div>
        {numerico('frecuencia_cardiaca', 'FC', <HeartPulse className="h-3 w-3" />, '72')}
        {numerico('frecuencia_respiratoria', 'FR', <Wind className="h-3 w-3" />, '16')}
        {numerico('temperatura', 'Temp', <Thermometer className="h-3 w-3" />, '36.5')}
        <div>
          <div className="flex items-center justify-between">
            <Label htmlFor="vital-peso" className="text-xs flex items-center gap-1"><Scale className="h-3 w-3" /> Peso ({unidadPeso})</Label>
            <div className="flex rounded border border-slate-200 overflow-hidden text-[10px]">
              <button type="button" onClick={() => cambiarUnidad('kg')} className={unidadPeso === 'kg' ? 'px-1.5 bg-[#1E5C8E] text-white' : 'px-1.5 bg-white text-slate-500'}>kg</button>
              <button type="button" onClick={() => cambiarUnidad('lb')} className={unidadPeso === 'lb' ? 'px-1.5 bg-[#1E5C8E] text-white' : 'px-1.5 bg-white text-slate-500'}>lb</button>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <Input id="vital-peso" type="number" inputMode="decimal" min={rangoPeso.min} max={rangoPeso.max} step={rangoPeso.step}
              placeholder={unidadPeso === 'lb' ? '154.0' : '70.0'} value={pesoBuf}
              onChange={e => { setPesoBuf(e.target.value); cambiar('peso_kg', inputAKg(e.target.value, unidadPeso)) }}
              aria-invalid={!!errores.peso_kg}
              className={`h-8 text-sm ${errores.peso_kg ? 'border-red-500' : ''}`} />
            <span className="text-xs font-semibold text-[#1E5C8E] w-5 shrink-0">{unidadPeso}</span>
          </div>
          <ErrorCampo msg={errores.peso_kg} />
        </div>
        {numerico('talla_cm', 'Talla', <Ruler className="h-3 w-3" />, '170')}
        {numerico('saturacion_o2', 'SpO2', <Gauge className="h-3 w-3" />, '98')}
        {numerico('glucosa', 'Glucosa', <Droplets className="h-3 w-3" />, '90')}
      </div>
      <div>
        <Label className="text-xs">Notas</Label>
        <Input value={values.notas} onChange={e => cambiar('notas', e.target.value)} className="h-8 text-sm" placeholder="Observaciones" />
      </div>
      {imc && (
        <div className="bg-slate-50 p-2 rounded text-center text-sm">
          <span className="text-muted-foreground">IMC: </span>
          <span className="font-bold text-[#1E5C8E]">{imc}</span>
        </div>
      )}
      <ErrorCampo msg={errores.imc} />
      {errorGeneral && <p role="alert" className="text-xs text-red-600">{errorGeneral}</p>}
      <Button type="submit" disabled={loading} className="w-full bg-[#1E5C8E] hover:bg-[#164a70]">
        {loading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Guardando…</> : 'Guardar toma'}
      </Button>
    </form>
  )
}
