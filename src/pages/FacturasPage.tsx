import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { usePacientes } from '@/hooks/usePacientes'
import { useFacturas } from '@/hooks/useFacturas'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { FileText, Plus, Search, DollarSign, Printer, Loader2, X } from 'lucide-react'

const METODOS_PAGO = [
  { value: 'efectivo', label: 'Efectivo' },
  { value: 'tarjeta', label: 'Tarjeta de Crédito/Débito' },
  { value: 'transferencia', label: 'Transferencia Bancaria' },
  { value: 'cheque', label: 'Cheque' },
  { value: 'seguro', label: 'Seguro Médico' }
]

const ESTADOS_FACTURA = [
  { value: 'pendiente', color: 'bg-yellow-100 text-yellow-700 border-yellow-200' },
  { value: 'pagada', color: 'bg-green-100 text-green-700 border-green-200' },
  { value: 'cancelada', color: 'bg-red-100 text-red-700 border-red-200' }
]

export default function FacturasPage() {
  const [searchParams] = useSearchParams()
  const { pacientes } = usePacientes()
  const { facturas, loading, createFactura, updateFactura } = useFacturas()

  const [showForm, setShowForm] = useState(searchParams.get('nuevo') === 'true')
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState('')

  const [form, setForm] = useState({
    paciente_id: '',
    concepto: '',
    cantidad: 1,
    precio_unitario: '',
    descuento: 0,
    metodo_pago: '',
    estado: 'pendiente',
    notas: ''
  })

  const [formError, setFormError] = useState('')

  const filtered = facturas.filter(f =>
    (f.paciente_nombre || '').toLowerCase().includes(search.toLowerCase()) ||
    f.concepto.toLowerCase().includes(search.toLowerCase())
  )

  const totalPendiente = facturas
    .filter(f => f.estado === 'pendiente')
    .reduce((sum, f) => sum + Number(f.total), 0)

  const totalPagado = facturas
    .filter(f => f.estado === 'pagada')
    .reduce((sum, f) => sum + Number(f.total), 0)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setFormError('')

    const { error } = await createFactura({
      paciente_id: parseInt(form.paciente_id),
      concepto: form.concepto,
      cantidad: form.cantidad,
      precio_unitario: parseFloat(form.precio_unitario),
      descuento: form.descuento,
      metodo_pago: form.metodo_pago || null,
      estado: form.estado as any,
      notas: form.notas || null
    })

    if (error) {
      setFormError(typeof error === 'string' ? error : 'Error al crear factura')
      setSaving(false)
      return
    }

    setForm({
      paciente_id: '', concepto: '', cantidad: 1, precio_unitario: '',
      descuento: 0, metodo_pago: '', estado: 'pendiente', notas: ''
    })
    setShowForm(false)
    setSaving(false)
  }

  const getEstadoColor = (estado: string) => {
    return ESTADOS_FACTURA.find(e => e.value === estado)?.color || 'bg-gray-100 text-gray-700'
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a]">Facturación</h1>
          <p className="text-[#8a9aaa] mt-1">Gestión de facturas y pagos</p>
        </div>
        <Button onClick={() => setShowForm(true)} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
          <Plus className="h-4 w-4 mr-2" /> Nueva Factura
        </Button>
      </div>

      {/* Resumen */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="border-l-4 border-l-[#1E5C8E]">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Total Facturado</p>
            <p className="text-2xl font-bold text-[#1a2a3a]">
              Q{facturas.reduce((sum, f) => sum + Number(f.total), 0).toFixed(2)}
            </p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-yellow-500">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Pendiente de Pago</p>
            <p className="text-2xl font-bold text-yellow-600">
              Q{totalPendiente.toFixed(2)}
            </p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-green-500">
          <CardContent className="p-4">
            <p className="text-xs text-[#8a9aaa] uppercase">Total Pagado</p>
            <p className="text-2xl font-bold text-green-600">
              Q{totalPagado.toFixed(2)}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Lista de facturas */}
      <Card>
        <CardHeader className="pb-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
            <Input
              placeholder="Buscar por paciente o concepto..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-10"
            />
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" /></div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-[#8a9aaa]">
              <FileText className="h-12 w-12 mx-auto mb-3 opacity-50" />
              <p>No hay facturas registradas</p>
            </div>
          ) : (
            <div className="divide-y">
              {filtered.map((f) => (
                <div key={f.id} className="p-4 flex items-center justify-between hover:bg-[#e8f0f8] transition-colors">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
                      <p className="font-medium truncate">{f.paciente_nombre || 'Paciente #' + f.paciente_id}</p>
                      <Badge variant="outline" className={getEstadoColor(f.estado)}>
                        {f.estado}
                      </Badge>
                    </div>
                    <p className="text-sm text-[#8a9aaa]">{f.concepto}</p>
                    <p className="text-xs text-[#8a9aaa]">
                      {new Date(f.fecha_emision).toLocaleDateString('es-GT')} - 
                      {f.metodo_pago ? ` ${f.metodo_pago}` : ' Sin método de pago'}
                    </p>
                  </div>
                  <div className="flex items-center gap-4 ml-4">
                    <p className="text-lg font-bold text-[#1E5C8E]">Q{Number(f.total).toFixed(2)}</p>
                    <div className="flex gap-1">
                      {f.estado === 'pendiente' && (
                        <Button 
                          variant="ghost" 
                          size="sm"
                          onClick={() => updateFactura(f.id, { estado: 'pagada' })}
                          title="Marcar como pagada"
                        >
                          <DollarSign className="h-4 w-4 text-green-600" />
                        </Button>
                      )}
                      <Button variant="ghost" size="sm" title="Imprimir factura">
                        <Printer className="h-4 w-4 text-[#1E5C8E]" />
                      </Button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Dialog: Nueva Factura */}
      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <DollarSign className="h-5 w-5 text-[#1E5C8E]" />
              Nueva Factura
            </DialogTitle>
          </DialogHeader>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label>Paciente *</Label>
              <Select value={form.paciente_id} onValueChange={(v) => setForm({...form, paciente_id: v})}>
                <SelectTrigger><SelectValue placeholder="Seleccionar paciente" /></SelectTrigger>
                <SelectContent>
                  {pacientes.map(p => (
                    <SelectItem key={p.id} value={String(p.id)}>{p.nombre} {p.apellido}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label>Concepto *</Label>
              <Input 
                value={form.concepto}
                onChange={e => setForm({...form, concepto: e.target.value})}
                placeholder="Ej: Consulta general, Receta médica, etc."
                required
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Cantidad</Label>
                <Input 
                  type="number"
                  min={1}
                  value={form.cantidad}
                  onChange={e => setForm({...form, cantidad: parseInt(e.target.value) || 1})}
                />
              </div>
              <div className="space-y-2">
                <Label>Precio Unitario (Q) *</Label>
                <Input 
                  type="number"
                  step="0.01"
                  min={0}
                  value={form.precio_unitario}
                  onChange={e => setForm({...form, precio_unitario: e.target.value})}
                  placeholder="0.00"
                  required
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Descuento (Q)</Label>
                <Input 
                  type="number"
                  step="0.01"
                  min={0}
                  value={form.descuento}
                  onChange={e => setForm({...form, descuento: parseFloat(e.target.value) || 0})}
                  placeholder="0.00"
                />
              </div>
              <div className="space-y-2">
                <Label>Método de Pago</Label>
                <Select value={form.metodo_pago} onValueChange={(v) => setForm({...form, metodo_pago: v})}>
                  <SelectTrigger><SelectValue placeholder="Seleccionar" /></SelectTrigger>
                  <SelectContent>
                    {METODOS_PAGO.map(m => (
                      <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            {/* Preview del total */}
            <Card className="bg-[#e8f0f8]">
              <CardContent className="p-4">
                <div className="flex justify-between items-center">
                  <span className="text-sm text-[#8a9aaa]">Subtotal:</span>
                  <span className="font-medium">Q{(form.cantidad * parseFloat(form.precio_unitario || '0')).toFixed(2)}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-sm text-[#8a9aaa]">Descuento:</span>
                  <span className="font-medium text-red-500">-Q{form.descuento.toFixed(2)}</span>
                </div>
                <div className="flex justify-between items-center border-t pt-2 mt-2">
                  <span className="font-bold">Total:</span>
                  <span className="font-bold text-xl text-[#1E5C8E]">
                    Q{((form.cantidad * parseFloat(form.precio_unitario || '0')) - form.descuento).toFixed(2)}
                  </span>
                </div>
              </CardContent>
            </Card>

            <div className="space-y-2">
              <Label>Notas</Label>
              <textarea 
                className="w-full border rounded-md p-3 min-h-[80px]"
                value={form.notas}
                onChange={e => setForm({...form, notas: e.target.value})}
                placeholder="Notas adicionales..."
              />
            </div>

            {formError && (
              <p className="text-sm text-red-500 bg-red-50 p-2 rounded">{formError}</p>
            )}

            <div className="flex justify-end gap-3">
              <Button type="button" variant="outline" onClick={() => setShowForm(false)}>
                <X className="h-4 w-4 mr-2" /> Cancelar
              </Button>
              <Button type="submit" className="bg-[#1E5C8E] hover:bg-[#3A8ABF]" disabled={saving}>
                {saving ? 'Guardando...' : 'Crear Factura'}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
