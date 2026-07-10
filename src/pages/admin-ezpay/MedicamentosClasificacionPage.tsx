import { useState, useCallback, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Pill, Loader2, ShieldAlert, Download, Save } from 'lucide-react'

interface Categoria {
  codigo: string
  etiqueta: string
  orden: number
  requiere_acuse: boolean
}

interface Medicamento {
  id: number
  nombre_generico: string
  nombre_comercial: string | null
  concentracion: string | null
  presentacion: string | null
  categoria_regulatoria: string | null
}

export default function MedicamentosClasificacionPage() {
  const [cats, setCats] = useState<Categoria[]>([])
  const [meds, setMeds] = useState<Medicamento[]>([])
  const [pend, setPend] = useState<Record<number, string>>({})   // id -> categoria elegida sin guardar
  const [motivo, setMotivo] = useState('')
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [noAutorizado, setNoAutorizado] = useState(false)

  const cargar = useCallback(async () => {
    setLoading(true)
    const [rc, rm] = await Promise.all([
      supabase.from('medicamentos_categorias').select('codigo, etiqueta, orden, requiere_acuse').order('orden'),
      supabase.from('medicamentos').select('id, nombre_generico, nombre_comercial, concentracion, presentacion, categoria_regulatoria').eq('activo', true).order('nombre_generico'),
    ])
    setLoading(false)
    if (rc.error) { toast.error('Error cargando categorias: ' + rc.error.message); return }
    if (rm.error) { toast.error('Error cargando medicamentos: ' + rm.error.message); return }
    setCats((rc.data ?? []) as Categoria[])
    setMeds((rm.data ?? []) as Medicamento[])
    setPend({})
  }, [])

  useEffect(() => { cargar() }, [cargar])

  const elegir = (id: number, codigo: string) => {
    setPend(prev => {
      const next = { ...prev }
      const med = meds.find(m => m.id === id)
      if (med && (med.categoria_regulatoria ?? '') === codigo) { delete next[id] }
      else { next[id] = codigo }
      return next
    })
  }

  const cambios = Object.keys(pend).length

  const guardar = async () => {
    if (cambios === 0) return
    if (motivo.trim() === '') { toast.error('El motivo es obligatorio'); return }
    setGuardando(true)
    const items = Object.entries(pend).map(([id, categoria]) => ({ medicamento_id: Number(id), categoria }))
    const { error } = await supabase.rpc('clasificar_medicamentos', { p_items: items, p_motivo: motivo.trim() })
    setGuardando(false)
    if (error) {
      if ((error.code ?? '').startsWith('PC')) { toast.error(error.message); return }
      if (/PC002|super_admin/.test(error.message ?? '')) { setNoAutorizado(true); return }
      toast.error('No se pudo clasificar. Intenta de nuevo.')
      return
    }
    toast.success(`${cambios} medicamento(s) clasificado(s)`)
    setMotivo('')
    cargar()
  }

  const exportarCSV = () => {
    const cab = ['id', 'nombre_generico', 'nombre_comercial', 'concentracion', 'presentacion', 'categoria_regulatoria']
    const esc = (v: unknown) => {
      const s = v == null ? '' : String(v)
      return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
    }
    const filas = meds.map(m => cab.map(c => esc((m as unknown as Record<string, unknown>)[c])).join(','))
    const csv = [cab.join(','), ...filas].join('\n')
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `catalogo-medicamentos-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  if (noAutorizado) {
    return (
      <div className="flex items-center gap-3 p-6 text-slate-600">
        <ShieldAlert className="h-5 w-5 text-red-500" />
        Solo un super administrador puede clasificar medicamentos.
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4 flex-wrap">
        <div className="flex items-center gap-2">
          <Pill className="h-6 w-6 text-slate-700" />
          <h1 className="text-xl font-semibold text-slate-800">Clasificación regulatoria de medicamentos</h1>
        </div>
        <Button variant="outline" onClick={exportarCSV} disabled={loading || meds.length === 0}>
          <Download className="h-4 w-4 mr-2" /> Exportar CSV
        </Button>
      </div>

      <p className="text-sm text-slate-500">
        Sin clasificar = no regulado (no exige acuse). Reclasificar no afecta recetas ya emitidas.
      </p>

      {loading ? (
        <div className="flex items-center gap-2 p-6 text-slate-500">
          <Loader2 className="h-4 w-4 animate-spin" /> Cargando…
        </div>
      ) : (
        <>
          <Card>
            <CardContent className="p-0 divide-y divide-slate-100">
              {meds.map(m => {
                const actual = m.categoria_regulatoria ?? ''
                const elegida = pend[m.id] ?? actual
                const sucio = m.id in pend
                return (
                  <div key={m.id} className={`flex items-center justify-between gap-4 p-3 ${sucio ? 'bg-amber-50' : ''}`}>
                    <div className="min-w-0">
                      <div className="font-medium text-slate-800 truncate">{m.nombre_generico}</div>
                      <div className="text-xs text-slate-500 truncate">
                        {[m.nombre_comercial, m.concentracion, m.presentacion].filter(Boolean).join(' · ')}
                      </div>
                    </div>
                    <select
                      className="border border-slate-200 rounded-md px-2 py-1 text-sm bg-white shrink-0"
                      value={elegida}
                      onChange={e => elegir(m.id, e.target.value)}
                    >
                      <option value="">Sin clasificar</option>
                      {cats.map(c => (
                        <option key={c.codigo} value={c.codigo}>
                          {c.etiqueta}{c.requiere_acuse ? ' (acuse)' : ''}
                        </option>
                      ))}
                    </select>
                  </div>
                )
              })}
            </CardContent>
          </Card>

          <div className="sticky bottom-0 bg-white border-t border-slate-200 p-3 flex items-center gap-3 flex-wrap">
            <input
              className="flex-1 min-w-[200px] border border-slate-200 rounded-md px-3 py-2 text-sm"
              placeholder="Motivo (obligatorio): ej. listado DRACES 2026"
              value={motivo}
              onChange={e => setMotivo(e.target.value)}
            />
            <span className="text-sm text-slate-500">{cambios} cambio(s)</span>
            <Button onClick={guardar} disabled={cambios === 0 || guardando}>
              {guardando ? <Loader2 className="h-4 w-4 mr-2 animate-spin" /> : <Save className="h-4 w-4 mr-2" />}
              Guardar clasificación
            </Button>
          </div>
        </>
      )}
    </div>
  )
}
