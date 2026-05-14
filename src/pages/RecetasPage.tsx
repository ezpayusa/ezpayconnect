import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { usePacientes } from '@/hooks/usePacientes'
import { useRecetas, useMedicamentos } from '@/hooks/useRecetas'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { FileText, Plus, Trash2, Search, Printer, Loader2 } from 'lucide-react'
import type { RecetaItem } from '@/types'

export default function RecetasPage() {
  const [searchParams] = useSearchParams()
  const { pacientes } = usePacientes()
  const { recetas, loading, createReceta } = useRecetas()
  const { medicamentos, loading: loadingMeds, error: errorMeds, fetchMedicamentos } = useMedicamentos()
  const [showForm, setShowForm] = useState(searchParams.get('nuevo') === 'true')
  const [saving, setSaving] = useState(false)
  const [searchMed, setSearchMed] = useState('')

  const [form, setForm] = useState({
    paciente_id: '', instrucciones_generales: ''
  })
  const [items, setItems] = useState<Partial<RecetaItem>[]>([])

  const handleAddMedicamento = (med: typeof medicamentos[0]) => {
    setItems([...items, {
      medicamento_id: med.id,
      nombre_medicamento: med.nombre_generico + (med.nombre_comercial ? ` (${med.nombre_comercial})` : ''),
      dosis: '', frecuencia: '', duracion: '', instrucciones: '', cantidad: 1
    }])
  }

  const updateItem = (idx: number, field: string, value: string | number) => {
    const newItems = [...items]
    newItems[idx] = { ...newItems[idx], [field]: value }
    setItems(newItems)
  }

  const removeItem = (idx: number) => {
    setItems(items.filter((_, i) => i !== idx))
  }

  const [formError, setFormError] = useState('')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (items.length === 0) return
    setSaving(true)
    setFormError('')
    const { error } = await createReceta(
      { paciente_id: parseInt(form.paciente_id), instrucciones_generales: form.instrucciones_generales },
      items as RecetaItem[]
    )
    if (error) {
      setFormError(typeof error === 'string' ? error : 'Error al generar receta. Verifica que seleccionaste un paciente y agregaste medicamentos.')
      setSaving(false)
      return
    }
    setForm({ paciente_id: '', instrucciones_generales: '' })
    setItems([])
    setShowForm(false)
    setSaving(false)
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a]">Recetas Medicas</h1>
          <p className="text-[#8a9aaa] mt-1">Generacion y gestion de recetas</p>
        </div>
        <Button onClick={() => setShowForm(true)} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
          <Plus className="h-4 w-4 mr-2" /> Nueva Receta
        </Button>
      </div>

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" /></div>
          ) : recetas.length === 0 ? (
            <div className="text-center py-12 text-[#8a9aaa]">
              <FileText className="h-12 w-12 mx-auto mb-3 opacity-50" />
              <p>No hay recetas registradas</p>
            </div>
          ) : (
            <div className="divide-y">
              {recetas.map((r) => (
                <div key={r.id} className="p-4 flex items-center justify-between hover:bg-[#e8f0f8] transition-colors">
                  <div>
                    <p className="font-medium">{r.paciente_nombre || 'Paciente #' + r.paciente_id}</p>
                    <p className="text-sm text-[#8a9aaa]">{new Date(r.created_at).toLocaleDateString('es-GT')} - {r.estado}</p>
                  </div>
                  <div className="flex gap-2">
                    <Button variant="ghost" size="sm"><Printer className="h-4 w-4" /></Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Nueva Receta Medica</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-6">
            <div className="space-y-2">
              <Label>Paciente *</Label>
              <Select value={form.paciente_id} onValueChange={(v) => setForm({...form, paciente_id: v})}>
                <SelectTrigger><SelectValue placeholder="Seleccionar paciente" /></SelectTrigger>
                <SelectContent>
                  {pacientes.map(p => <SelectItem key={p.id} value={String(p.id)}>{p.nombre} {p.apellido}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>

            <Card className="border-dashed">
              <CardHeader>
                <CardTitle className="text-base">Buscar Medicamentos</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
                  <Input
                    placeholder="Buscar por nombre..."
                    value={searchMed}
                    onChange={(e) => { setSearchMed(e.target.value); fetchMedicamentos(e.target.value) }}
                    className="pl-10"
                  />
                </div>
                     {errorMeds && (
                  <p className="text-xs text-red-500 bg-red-50 p-2 rounded">{errorMeds}</p>
                )}
                {loadingMeds && (
                  <div className="text-center py-2 text-[#8a9aaa] text-sm"><Loader2 className="h-4 w-4 animate-spin inline mr-1" /> Buscando...</div>
                )}
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

            {items.length > 0 && (
              <div className="space-y-4">
                <h3 className="font-medium">Medicamentos Prescritos ({items.length})</h3>
                {items.map((item, idx) => (
                  <Card key={idx} className="bg-[#e8f0f8]">
                    <CardContent className="p-4 space-y-3">
                      <div className="flex items-center justify-between">
                        <p className="font-medium text-sm text-[#1E5C8E]">{item.nombre_medicamento}</p>
                        <Button type="button" variant="ghost" size="sm" onClick={() => removeItem(idx)}>
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      </div>
                      <div className="grid grid-cols-2 gap-3">
                        <div className="space-y-1"><Label className="text-xs">Dosis *</Label><Input size={1} className="h-8 text-sm" value={item.dosis} onChange={e => updateItem(idx, 'dosis', e.target.value)} placeholder="500mg" required /></div>
                        <div className="space-y-1"><Label className="text-xs">Frecuencia *</Label><Input className="h-8 text-sm" value={item.frecuencia} onChange={e => updateItem(idx, 'frecuencia', e.target.value)} placeholder="Cada 8 horas" required /></div>
                        <div className="space-y-1"><Label className="text-xs">Duracion</Label><Input className="h-8 text-sm" value={item.duracion || ''} onChange={e => updateItem(idx, 'duracion', e.target.value)} placeholder="7 dias" /></div>
                        <div className="space-y-1"><Label className="text-xs">Cantidad</Label><Input type="number" className="h-8 text-sm" value={item.cantidad} onChange={e => updateItem(idx, 'cantidad', parseInt(e.target.value) || 1)} min={1} /></div>
                      </div>
                      <div className="space-y-1"><Label className="text-xs">Instrucciones</Label><Input className="h-8 text-sm" value={item.instrucciones || ''} onChange={e => updateItem(idx, 'instrucciones', e.target.value)} placeholder="Tomar despues de las comidas" /></div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}

            <div className="space-y-2">
              <Label>Instrucciones Generales</Label>
              <textarea
                className="w-full border rounded-md p-3 min-h-[80px]"
                value={form.instrucciones_generales}
                onChange={e => setForm({...form, instrucciones_generales: e.target.value})}
                placeholder="Instrucciones generales para el paciente..."
              />
            </div>

            {formError && (
              <p className="text-sm text-red-500 bg-red-50 p-2 rounded">{formError}</p>
            )}
            <div className="flex justify-end gap-3">
              <Button type="button" variant="outline" onClick={() => { setShowForm(false); setFormError('') }}>Cancelar</Button>
              <Button type="submit" className="bg-[#1E5C8E] hover:bg-[#3A8ABF]" disabled={saving || items.length === 0}>
                {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Generar Receta
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
