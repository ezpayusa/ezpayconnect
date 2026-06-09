import { useState, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useAuth } from '@/hooks/useAuth'
import { usePacientes } from '@/hooks/usePacientes'
import { useRecetas, useMedicamentos } from '@/hooks/useRecetas'
import { useBusquedaMedicamentos } from '@/hooks/useBusquedaMedicamentos'
import { toast } from 'sonner'
import type { RecetaItem } from '@/types'
import {
  Search,
  Plus,
  Trash2,
  Loader2,
  Home,
  FlaskConical,
  CheckCircle2,
  AlertCircle,
} from 'lucide-react'

interface RecetaModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  pacienteIdPreseleccionado?: string
  citaId?: number | null
  onSuccess?: () => void
}

function limpiarNombreParaBusqueda(nombre: string): string {
  if (!nombre) return ''
  return nombre.replace(/\s*\(.*?\)/g, '').trim()
}

export default function RecetaModal({ open, onOpenChange, pacienteIdPreseleccionado, citaId, onSuccess }: RecetaModalProps) {
  const { perfil } = useAuth()
  const { pacientes } = usePacientes()
  const { createReceta } = useRecetas()
  const { medicamentos, loading: loadingMeds, error: errorMeds, fetchMedicamentos } = useMedicamentos()
  const { resultados: resultadosBusqueda, loading: loadingBusqueda, buscar: buscarEnProveedor } = useBusquedaMedicamentos()

  const [form, setForm] = useState({ paciente_id: pacienteIdPreseleccionado || '', instrucciones_generales: '' })
  const [items, setItems] = useState<Partial<RecetaItem>[]>([])
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState('')
  const [searchMed, setSearchMed] = useState('')
  const [alertasMedicamentos, setAlertasMedicamentos] = useState<{idx: number; mensaje: string; tipo: 'alergia' | 'interaccion'}[]>([])

  // Modales farmacia/laboratorio
  const [showFarmaciaModal, setShowFarmaciaModal] = useState(false)
  const [showLaboratorioModal, setShowLaboratorioModal] = useState(false)
  const [itemIdxBuscando, setItemIdxBuscando] = useState<number | null>(null)
  const [busquedaProveedor, setBusquedaProveedor] = useState('')

  // Preseleccionar paciente
  useEffect(() => {
    if (pacienteIdPreseleccionado) {
      setForm(prev => ({ ...prev, paciente_id: pacienteIdPreseleccionado }))
    }
  }, [pacienteIdPreseleccionado])

  // Limpiar al cerrar
  useEffect(() => {
    if (!open) {
      setForm({ paciente_id: pacienteIdPreseleccionado || '', instrucciones_generales: '' })
      setItems([])
      setFormError('')
      setSearchMed('')
    }
  }, [open, pacienteIdPreseleccionado])

  const verificarAlertas = (nombreMed: string, idx: number) => {
    const nuevasAlertas: {idx: number; mensaje: string; tipo: 'alergia' | 'interaccion'}[] = []
    const nombreLower = nombreMed.toLowerCase()

    // Verificar alergias
    if (pacienteSeleccionado?.alergias) {
      const alergias = pacienteSeleccionado.alergias.toLowerCase().split(/[,;]/).map(a => a.trim()).filter(Boolean)
      for (const alergia of alergias) {
        if (alergia.length > 2 && nombreLower.includes(alergia)) {
          nuevasAlertas.push({ idx, mensaje: `⚠️ El medicamento contiene "${alergia}". El paciente tiene alergia registrada a: ${pacienteSeleccionado.alergias}`, tipo: 'alergia' })
        }
      }
    }

    // Verificar medicamentos en uso (recordatorio, no alerta estricta)
    if (pacienteSeleccionado?.medicamentos_en_uso) {
      nuevasAlertas.push({ idx, mensaje: `💊 Paciente toma: ${pacienteSeleccionado.medicamentos_en_uso}. Verificar interacciones.`, tipo: 'interaccion' })
    }

    if (nuevasAlertas.length > 0) {
      setAlertasMedicamentos(prev => [...prev, ...nuevasAlertas])
    }
  }

  const handleAddMedicamento = (med: typeof medicamentos[0]) => {
    const nuevoItem = {
      medicamento_id: med.id,
      nombre_medicamento: med.nombre_generico + (med.nombre_comercial ? ` (${med.nombre_comercial})` : ''),
      dosis: '', frecuencia: '', duracion: '', instrucciones: '', cantidad: 1,
      farmacia_id: null
    }
    const newIdx = items.length
    setItems([...items, nuevoItem])
    verificarAlertas(nuevoItem.nombre_medicamento, newIdx)
  }

  const updateItem = (idx: number, field: string, value: string | number) => {
    const newItems = [...items]
    newItems[idx] = { ...newItems[idx], [field]: value }
    setItems(newItems)
  }

  const removeItem = (idx: number) => {
    setItems(items.filter((_, i) => i !== idx))
  }

  const abrirModalFarmacia = (idx: number) => {
    setItemIdxBuscando(idx)
    const nombre = limpiarNombreParaBusqueda(items[idx]?.nombre_medicamento || '')
    setBusquedaProveedor(nombre)
    if (nombre.trim()) buscarEnProveedor(nombre)
    setShowFarmaciaModal(true)
  }

  const abrirModalLaboratorio = (idx: number) => {
    setItemIdxBuscando(idx)
    const nombre = limpiarNombreParaBusqueda(items[idx]?.nombre_medicamento || '')
    setBusquedaProveedor(nombre)
    if (nombre.trim()) buscarEnProveedor(nombre)
    setShowLaboratorioModal(true)
  }

  const seleccionarProveedor = (proveedor: any) => {
    if (itemIdxBuscando === null) return
    const newItems = [...items]
    newItems[itemIdxBuscando] = {
      ...newItems[itemIdxBuscando],
      farmacia_id: proveedor.farmacia?.id || null,
      precio_unitario: proveedor.precio_unitario || null,
      stock_actual: proveedor.stock_actual || null
    }
    setItems(newItems)
    setShowFarmaciaModal(false)
    setShowLaboratorioModal(false)
    setItemIdxBuscando(null)
    setBusquedaProveedor('')
  }

  const renderResultadosBusqueda = (tipoFiltro: 'farmacia' | 'laboratorio') => {
    const filtrados = resultadosBusqueda.filter((r: any) => {
      if (!r.farmacia) return false
      if (r.farmacia.tipo === undefined || r.farmacia.tipo === null) return true
      return r.farmacia.tipo === tipoFiltro
    })

    if (loadingBusqueda) {
      return (
        <div className="text-center py-4 text-[#8a9aaa] text-sm">
          <Loader2 className="h-4 w-4 animate-spin inline mr-1" /> Buscando...
        </div>
      )
    }

    if (!loadingBusqueda && busquedaProveedor.trim().length > 0 && filtrados.length === 0) {
      return (
        <p className="text-sm text-[#8a9aaa] text-center py-4">
          No se encontraron resultados en {tipoFiltro === 'farmacia' ? 'farmacias' : 'laboratorios'}
        </p>
      )
    }

    return (
      <div className="space-y-2 max-h-96 overflow-y-auto">
        {filtrados.map((r: any) => (
          <Card key={r.id} className="border-l-4 border-l-[#1E5C8E] hover:bg-[#e8f0f8] transition-colors">
            <CardContent className="p-3 flex justify-between items-center gap-3">
              <div className="flex-1 min-w-0">
                <p className="font-medium text-sm text-[#1a2a3a] truncate">{r.nombre_medicamento}</p>
                <p className="text-xs text-[#8a9aaa] mt-0.5">
                  <span className="font-medium text-[#1E5C8E]">{r.farmacia?.nombre || 'Sin proveedor'}</span>
                  {r.farmacia?.direccion && <span> · {r.farmacia.direccion}</span>}
                </p>
                <p className="text-xs text-[#8a9aaa] mt-0.5">
                  Stock: <span className="font-medium">{r.stock_actual}</span>
                  {' · '}
                  Precio: <span className="font-medium">Q{r.precio_unitario}</span>
                  {r.farmacia?.telefono && <span> · Tel: {r.farmacia.telefono}</span>}
                </p>
              </div>
              <Button type="button" size="sm" className="bg-[#1E5C8E] hover:bg-[#3A8ABF] shrink-0" onClick={() => seleccionarProveedor(r)}>
                Seleccionar
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>
    )
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.paciente_id) {
      setFormError('Selecciona un paciente')
      return
    }
    if (items.length === 0) {
      setFormError('Agrega al menos un medicamento')
      return
    }
    for (const item of items) {
      if (!item.dosis || !item.frecuencia) {
        setFormError('Todos los medicamentos deben tener dosis y frecuencia')
        return
      }
    }

    setSaving(true)
    setFormError('')

    const result = await createReceta(
      {
        paciente_id: parseInt(form.paciente_id),
        instrucciones_generales: form.instrucciones_generales || null,
        cita_id: citaId || null,
      },
      items as RecetaItem[]
    )

    if (result.error) {
      setFormError(result.error)
      toast.error(result.error)
    } else {
      toast.success('Receta creada exitosamente')
      setForm({ paciente_id: pacienteIdPreseleccionado || '', instrucciones_generales: '' })
      setItems([])
      onOpenChange(false)
      if (onSuccess) onSuccess()
    }

    setSaving(false)
  }

  const pacienteSeleccionado = pacientes.find(p => String(p.id) === form.paciente_id)

  const alertasPorItem = (idx: number) => alertasMedicamentos.filter(a => a.idx === idx)

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Nueva Receta Médica</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Paciente */}
            <div className="space-y-2">
              <Label>Paciente *</Label>
              <Select value={form.paciente_id} onValueChange={(v) => setForm({...form, paciente_id: v})}>
                <SelectTrigger><SelectValue placeholder="Seleccionar paciente" /></SelectTrigger>
                <SelectContent>
                  {pacientes.map(p => <SelectItem key={p.id} value={String(p.id)}>{p.nombre} {p.apellido}</SelectItem>)}
                </SelectContent>
              </Select>
              {pacienteSeleccionado?.alergias && (
                <div className="bg-red-50 border border-red-200 rounded-lg p-3 flex items-start gap-2">
                  <AlertCircle className="h-4 w-4 text-red-600 shrink-0 mt-0.5" />
                  <div>
                    <p className="text-sm font-medium text-red-700">Alergias del paciente</p>
                    <p className="text-sm text-red-600">{pacienteSeleccionado.alergias}</p>
                  </div>
                </div>
              )}
            </div>

            {/* Buscar medicamentos */}
            <Card className="border-dashed">
              <CardHeader>
                <CardTitle className="text-base">Buscar Medicamentos</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
                  <Input
                    placeholder="Buscar por nombre genérico o comercial..."
                    value={searchMed}
                    onChange={(e) => { setSearchMed(e.target.value); fetchMedicamentos(e.target.value) }}
                    className="pl-10"
                  />
                </div>
                {errorMeds && <p className="text-xs text-red-500 bg-red-50 p-2 rounded">{errorMeds}</p>}
                {loadingMeds && <div className="text-center py-2 text-[#8a9aaa] text-sm"><Loader2 className="h-4 w-4 animate-spin inline mr-1" /> Buscando...</div>}
                {!loadingMeds && searchMed.trim().length > 0 && medicamentos.length === 0 && (
                  <p className="text-sm text-[#8a9aaa] text-center py-2">No se encontraron medicamentos</p>
                )}
                {!loadingMeds && medicamentos.length > 0 && (
                  <div className="max-h-40 overflow-y-auto divide-y border rounded-lg">
                    {medicamentos.map(med => (
                      <div key={med.id} className="flex items-center justify-between p-3 hover:bg-gray-50">
                        <div>
                          <p className="font-medium text-sm">{med.nombre_generico}</p>
                          <p className="text-xs text-[#8a9aaa]">{med.presentacion} {med.concentracion}</p>
                        </div>
                        <Button type="button" size="sm" variant="outline" onClick={() => handleAddMedicamento(med)}>
                          <Plus className="h-3 w-3" />
                        </Button>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Items */}
            {items.length > 0 && (
              <div className="space-y-4">
                <h3 className="font-medium">Medicamentos Prescritos ({items.length})</h3>
                {items.map((item, idx) => (
                  <Card key={idx} className="bg-[#e8f0f8]">
                    <CardContent className="p-4 space-y-3">
                      {/* Alertas del medicamento */}
                      {alertasPorItem(idx).map((alerta, i) => (
                        <div key={i} className={`p-2 rounded text-xs flex items-start gap-2 ${
                          alerta.tipo === 'alergia' ? 'bg-red-100 text-red-700 border border-red-200' : 'bg-amber-50 text-amber-700 border border-amber-200'
                        }`}>
                          <AlertCircle className="h-3 w-3 shrink-0 mt-0.5" />
                          <span>{alerta.mensaje}</span>
                        </div>
                      ))}
                      <div className="flex items-center justify-between">
                        <p className="font-medium text-sm text-[#1E5C8E]">{item.nombre_medicamento}</p>
                        <Button type="button" variant="ghost" size="sm" onClick={() => removeItem(idx)}>
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      </div>
                      <div className="grid grid-cols-2 gap-3">
                        <div className="space-y-1"><Label className="text-xs">Dosis *</Label><Input className="h-8 text-sm" value={item.dosis} onChange={e => updateItem(idx, 'dosis', e.target.value)} placeholder="500mg" required /></div>
                        <div className="space-y-1"><Label className="text-xs">Frecuencia *</Label><Input className="h-8 text-sm" value={item.frecuencia} onChange={e => updateItem(idx, 'frecuencia', e.target.value)} placeholder="Cada 8 horas" required /></div>
                        <div className="space-y-1"><Label className="text-xs">Duración</Label><Input className="h-8 text-sm" value={item.duracion || ''} onChange={e => updateItem(idx, 'duracion', e.target.value)} placeholder="7 días" /></div>
                        <div className="space-y-1"><Label className="text-xs">Cantidad</Label><Input type="number" className="h-8 text-sm" value={item.cantidad} onChange={e => updateItem(idx, 'cantidad', parseInt(e.target.value) || 1)} min={1} /></div>
                      </div>
                      <div className="space-y-1"><Label className="text-xs">Instrucciones especiales</Label><Input className="h-8 text-sm" value={item.instrucciones || ''} onChange={e => updateItem(idx, 'instrucciones', e.target.value)} placeholder="Tomar después de las comidas" /></div>
                      <div className="flex items-center gap-2 pt-2 border-t border-[#1E5C8E]/10">
                        <Button type="button" size="sm" variant="outline" onClick={() => abrirModalFarmacia(idx)} className={item.farmacia_id ? 'border-green-500 text-green-700 hover:bg-green-50' : 'border-[#1E5C8E] text-[#1E5C8E] hover:bg-white'}>
                          {item.farmacia_id ? <CheckCircle2 className="h-3 w-3 mr-1" /> : <Home className="h-3 w-3 mr-1" />}
                          Farmacias
                        </Button>
                        <Button type="button" size="sm" variant="outline" onClick={() => abrirModalLaboratorio(idx)} className="border-[#3A8ABF] text-[#3A8ABF] hover:bg-white">
                          <FlaskConical className="h-3 w-3 mr-1" />
                          Laboratorios
                        </Button>
                        {item.farmacia_id && <span className="text-xs text-green-700 ml-1">✓ Proveedor asignado</span>}
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}

            {/* Instrucciones generales */}
            <div className="space-y-2">
              <Label>Instrucciones Generales</Label>
              <textarea
                className="w-full border rounded-md p-3 min-h-[80px] text-sm"
                value={form.instrucciones_generales}
                onChange={e => setForm({...form, instrucciones_generales: e.target.value})}
                placeholder="Instrucciones generales para el paciente..."
              />
            </div>

            {formError && <p className="text-sm text-red-500 bg-red-50 p-2 rounded">{formError}</p>}

            <div className="flex justify-end gap-3">
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
              <Button type="submit" className="bg-[#1E5C8E] hover:bg-[#3A8ABF]" disabled={saving || items.length === 0}>
                {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Generar Receta
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Modal Farmacia */}
      <Dialog open={showFarmaciaModal} onOpenChange={setShowFarmaciaModal}>
        <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Home className="h-5 w-5 text-[#1E5C8E]" />
              Buscar en Farmacias
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-[#8a9aaa]">
              Medicamento: <span className="font-medium text-[#1a2a3a]">{items[itemIdxBuscando ?? 0]?.nombre_medicamento}</span>
            </p>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
              <Input
                value={busquedaProveedor}
                onChange={e => { setBusquedaProveedor(e.target.value); buscarEnProveedor(e.target.value) }}
                placeholder="Buscar farmacia..."
                className="pl-10"
              />
            </div>
            {renderResultadosBusqueda('farmacia')}
          </div>
        </DialogContent>
      </Dialog>

      {/* Modal Laboratorio */}
      <Dialog open={showLaboratorioModal} onOpenChange={setShowLaboratorioModal}>
        <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <FlaskConical className="h-5 w-5 text-[#3A8ABF]" />
              Buscar en Laboratorios
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-[#8a9aaa]">
              Medicamento: <span className="font-medium text-[#1a2a3a]">{items[itemIdxBuscando ?? 0]?.nombre_medicamento}</span>
            </p>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
              <Input
                value={busquedaProveedor}
                onChange={e => { setBusquedaProveedor(e.target.value); buscarEnProveedor(e.target.value) }}
                placeholder="Buscar laboratorio..."
                className="pl-10"
              />
            </div>
            {renderResultadosBusqueda('laboratorio')}
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}
