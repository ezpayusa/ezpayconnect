import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { usePacientes } from '@/hooks/usePacientes'
import { useFacturas } from '@/hooks/useFacturas'
import { useEnviarFactura } from '@/hooks/useEnviarFactura'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { FileText, Plus, Search, DollarSign, Printer, Mail, Download, Loader2, X, Eye } from 'lucide-react'

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
  const { enviarFactura, enviando: enviandoEmail } = useEnviarFactura()
  const [showEmail, setShowEmail] = useState(false)
  const [emailTo, setEmailTo] = useState('')

  const [showForm, setShowForm] = useState(searchParams.get('nuevo') === 'true')
  const [showPreview, setShowPreview] = useState(false)
  const [selectedFactura, setSelectedFactura] = useState<any>(null)
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

  const openPreview = (factura: any) => {
    setSelectedFactura(factura)
    setShowPreview(true)
  }

  const handlePrint = () => {
    window.print()
  }

  const handleDownloadPDF = () => {
    // Simulación de descarga - en producción usarías jsPDF o similar
    const element = document.getElementById('factura-preview')
    if (element) {
      const printWindow = window.open('', '_blank')
      if (printWindow) {
        printWindow.document.write(`
          <html>
            <head><title>Factura ${selectedFactura?.id}</title>
            <style>
              body { font-family: Arial, sans-serif; padding: 40px; max-width: 800px; margin: 0 auto; }
              .header { text-align: center; border-bottom: 2px solid #1E5C8E; padding-bottom: 20px; margin-bottom: 30px; }
              .header h1 { color: #1E5C8E; margin: 0; }
              .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 30px; }
              .info-box { background: #f5f5f5; padding: 15px; border-radius: 8px; }
              .info-box h3 { margin: 0 0 10px 0; color: #1E5C8E; font-size: 14px; text-transform: uppercase; }
              table { width: 100%; border-collapse: collapse; margin: 20px 0; }
              th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
              th { background: #1E5C8E; color: white; }
              .total-row { font-size: 18px; font-weight: bold; color: #1E5C8E; }
              .footer { margin-top: 40px; text-align: center; color: #666; font-size: 12px; }
            </style>
            </head>
            <body>${element.innerHTML}</body>
          </html>
        `)
        printWindow.document.close()
        printWindow.print()
      }
    }
  }

  const handleSendEmail = () => {
    if (!selectedFactura) return
    setEmailTo(selectedFactura.pacientes?.email || '')
    setShowEmail(true)
  }

  const confirmarEnvioEmail = async () => {
    if (!selectedFactura || !emailTo) return
    const result = await enviarFactura({
      to: emailTo,
      facturaId: selectedFactura.id,
      pacienteNombre: selectedFactura.paciente_nombre || 'Paciente #' + selectedFactura.paciente_id,
      concepto: selectedFactura.concepto,
      cantidad: Number(selectedFactura.cantidad),
      precioUnitario: Number(selectedFactura.precio_unitario),
      descuento: Number(selectedFactura.descuento || 0),
      total: Number(selectedFactura.total),
      moneda: 'Q',
      fecha: selectedFactura.fecha_emision,
      estado: selectedFactura.estado,
      metodoPago: selectedFactura.metodo_pago || undefined,
      notas: selectedFactura.notas || undefined,
    })
    if (result.success) {
      toast.success('Factura enviada a ' + emailTo)
      setShowEmail(false)
      setShowPreview(false)
    } else {
      toast.error(result.error || 'No se pudo enviar la factura')
    }
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
                  <div className="flex items-center gap-2 ml-4">
                    <p className="text-lg font-bold text-[#1E5C8E]">Q{Number(f.total).toFixed(2)}</p>
                    <div className="flex gap-1">
                      <Button 
                        variant="ghost" 
                        size="sm"
                        onClick={() => openPreview(f)}
                        title="Ver factura"
                      >
                        <Eye className="h-4 w-4 text-[#1E5C8E]" />
                      </Button>
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

      {/* Dialog: Vista previa de Factura */}
      <Dialog open={showPreview} onOpenChange={setShowPreview}>
        <DialogContent className="max-w-3xl max-h-[95vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center justify-between">
              <span className="flex items-center gap-2">
                <FileText className="h-5 w-5 text-[#1E5C8E]" />
                Factura #{selectedFactura?.id}
              </span>
            </DialogTitle>
          </DialogHeader>

          {selectedFactura && (
            <div className="space-y-6">
              {/* Vista previa imprimible */}
              <div id="factura-preview" className="bg-white p-8 border rounded-lg">
                <div className="text-center border-b-2 border-[#1E5C8E] pb-4 mb-6">
                  <h2 className="text-2xl font-bold text-[#1E5C8E]">EzPayConnect</h2>
                  <p className="text-sm text-[#8a9aaa]">Software Médico - Factura #{selectedFactura.id}</p>
                </div>

                <div className="grid grid-cols-2 gap-4 mb-6">
                  <div className="bg-gray-50 p-4 rounded">
                    <h4 className="text-xs font-bold text-[#1E5C8E] uppercase mb-2">Paciente</h4>
                    <p className="font-medium">{selectedFactura.paciente_nombre || 'Paciente #' + selectedFactura.paciente_id}</p>
                  </div>
                  <div className="bg-gray-50 p-4 rounded">
                    <h4 className="text-xs font-bold text-[#1E5C8E] uppercase mb-2">Detalles</h4>
                    <p className="text-sm">Fecha: {new Date(selectedFactura.fecha_emision).toLocaleDateString('es-GT')}</p>
                    <p className="text-sm">Estado: <span className={getEstadoColor(selectedFactura.estado)}>{selectedFactura.estado}</span></p>
                    <p className="text-sm">Método: {selectedFactura.metodo_pago || 'N/A'}</p>
                  </div>
                </div>

                <table className="w-full mb-6">
                  <thead>
                    <tr className="bg-[#1E5C8E] text-white">
                      <th className="p-3 text-left">Concepto</th>
                      <th className="p-3 text-center">Cantidad</th>
                      <th className="p-3 text-right">Precio Unit.</th>
                      <th className="p-3 text-right">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr className="border-b">
                      <td className="p-3">{selectedFactura.concepto}</td>
                      <td className="p-3 text-center">{selectedFactura.cantidad}</td>
                      <td className="p-3 text-right">Q{Number(selectedFactura.precio_unitario).toFixed(2)}</td>
                      <td className="p-3 text-right">Q{(selectedFactura.cantidad * Number(selectedFactura.precio_unitario)).toFixed(2)}</td>
                    </tr>
                  </tbody>
                </table>

                <div className="border-t pt-4">
                  <div className="flex justify-between mb-2">
                    <span className="text-[#8a9aaa]">Subtotal:</span>
                    <span>Q{(selectedFactura.cantidad * Number(selectedFactura.precio_unitario)).toFixed(2)}</span>
                  </div>
                  {selectedFactura.descuento > 0 && (
                    <div className="flex justify-between mb-2">
                      <span className="text-[#8a9aaa]">Descuento:</span>
                      <span className="text-red-500">-Q{Number(selectedFactura.descuento).toFixed(2)}</span>
                    </div>
                  )}
                  <div className="flex justify-between text-xl font-bold text-[#1E5C8E] border-t pt-2">
                    <span>TOTAL:</span>
                    <span>Q{Number(selectedFactura.total).toFixed(2)}</span>
                  </div>
                </div>

                {selectedFactura.notas && (
                  <div className="mt-6 p-4 bg-gray-50 rounded text-sm">
                    <p className="font-medium mb-1">Notas:</p>
                    <p className="text-[#8a9aaa]">{selectedFactura.notas}</p>
                  </div>
                )}

                <div className="mt-8 text-center text-xs text-[#8a9aaa]">
                  <p>EzPayConnect - Software Médico</p>
                  <p>Gracias por preferirnos</p>
                </div>
              </div>

              {/* Botones de acción */}
              <div className="flex flex-wrap gap-3 justify-center">
                <Button onClick={handlePrint} variant="outline" className="border-[#1E5C8E] text-[#1E5C8E]">
                  <Printer className="h-4 w-4 mr-2" /> Imprimir
                </Button>
                <Button onClick={handleDownloadPDF} variant="outline" className="border-[#1E5C8E] text-[#1E5C8E]">
                  <Download className="h-4 w-4 mr-2" /> Descargar PDF
                </Button>
                <Button onClick={handleSendEmail} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
                  <Mail className="h-4 w-4 mr-2" /> Enviar por Email
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={showEmail} onOpenChange={setShowEmail}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Mail className="h-5 w-5 text-[#1E5C8E]" /> Enviar factura por email
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email-factura">Email del paciente</Label>
              <Input id="email-factura" type="email" placeholder="paciente@email.com" value={emailTo} onChange={e => setEmailTo(e.target.value)} disabled={enviandoEmail} />
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="outline" onClick={() => setShowEmail(false)} disabled={enviandoEmail}>Cancelar</Button>
              <Button onClick={confirmarEnvioEmail} disabled={!emailTo || enviandoEmail} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
                {enviandoEmail ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Enviando...</> : <><Mail className="h-4 w-4 mr-2" /> Enviar</>}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}