import { useState } from 'react'
import { useSearchParams } from 'react-router'
import { usePacientes } from '@/hooks/usePacientes'
import { useRecetas, useMedicamentos } from '@/hooks/useRecetas'
import { useBusquedaMedicamentos } from '@/hooks/useBusquedaMedicamentos'
import { useAuth } from '@/hooks/useAuth'
import { generarPDFReceta, imprimirPDFReceta } from '@/lib/pdfReceta'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { FileText, Plus, Trash2, Search, Printer, Eye, Loader2, X, Download, Mail, ArrowLeft, MapPin, FlaskConical, CheckCircle2 } from 'lucide-react'
import type { RecetaItem } from '@/types'
import EnviarRecetaEmail from '@/components/recetas/EnviarRecetaEmail'
import { useNavigate } from 'react-router-dom'

export default function RecetasPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const { pacientes } = usePacientes()
  const { recetas, loading, createReceta, getRecetaCompleta, updateReceta } = useRecetas()
  const { medicamentos, loading: loadingMeds, error: errorMeds, fetchMedicamentos } = useMedicamentos()
  const { perfil } = useAuth()

  // Hook de busqueda de medicamentos en farmacias/laboratorios
  const { resultados: resultadosBusqueda, loading: loadingBusqueda, buscar: buscarEnProveedor } = useBusquedaMedicamentos()

  const [showForm, setShowForm] = useState(searchParams.get('nuevo') === 'true')
  const [showDetail, setShowDetail] = useState(false)
  const [selectedReceta, setSelectedReceta] = useState<{
    receta: any, items: any[], paciente: any
  } | null>(null)
  const [saving, setSaving] = useState(false)
  const [searchMed, setSearchMed] = useState('')
  const [printingId, setPrintingId] = useState<number | null>(null)

  // Estado para modal de enviar email
  const [showEmailModal, setShowEmailModal] = useState(false)
  const [emailRecetaData, setEmailRecetaData] = useState<{
    receta: any, items: any[], paciente: any
  } | null>(null)

  // ============================================================
  // NUEVO: Estados para modales de Farmacia / Laboratorio
  // ============================================================
  const [showFarmaciaModal, setShowFarmaciaModal] = useState(false)
  const [showLaboratorioModal, setShowLaboratorioModal] = useState(false)
  const [itemIdxBuscando, setItemIdxBuscando] = useState<number | null>(null)
  const [busquedaProveedor, setBusquedaProveedor] = useState('')

  const [form, setForm] = useState({
    paciente_id: '', instrucciones_generales: ''
  })
  const [items, setItems] = useState<Partial<RecetaItem>[]>([])
  const [formError, setFormError] = useState('')

  const handleAddMedicamento = (med: typeof medicamentos[0]) => {
    setItems([...items, {
      medicamento_id: med.id,
      nombre_medicamento: med.nombre_generico + (med.nombre_comercial ? ` (${med.nombre_comercial})` : ''),
      dosis: '', frecuencia: '', duracion: '', instrucciones: '', cantidad: 1,
      farmacia_id: null
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

  // ============================================================
  // NUEVO: Abrir modal de Farmacia para un medicamento dado
  // ============================================================
  // ============================================================
  // NUEVO: Helper para limpiar nombre antes de buscar en proveedores
  // Quita "(Aspirina)" y similar para que el ILIKE matchee.
  // Ej: "Acido Acetilsalicilico (Aspirina)" -> "Acido Acetilsalicilico"
  // ============================================================
  const limpiarNombreParaBusqueda = (nombre: string): string => {
    if (!nombre) return ''
    return nombre.replace(/\s*\(.*?\)/g, '').trim()
  }

  // ============================================================
  // NUEVO: Abrir modal de Farmacia para un medicamento dado
  // ============================================================
  const abrirModalFarmacia = (idx: number) => {
    setItemIdxBuscando(idx)
    const nombre = limpiarNombreParaBusqueda(items[idx]?.nombre_medicamento || '')
    setBusquedaProveedor(nombre)
    if (nombre.trim()) buscarEnProveedor(nombre)
    setShowFarmaciaModal(true)
  }

  // ============================================================
  // NUEVO: Abrir modal de Laboratorio para un medicamento dado
  // ============================================================
  const abrirModalLaboratorio = (idx: number) => {
    setItemIdxBuscando(idx)
    const nombre = limpiarNombreParaBusqueda(items[idx]?.nombre_medicamento || '')
    setBusquedaProveedor(nombre)
    if (nombre.trim()) buscarEnProveedor(nombre)
    setShowLaboratorioModal(true)
  }

  // ============================================================
  // NUEVO: Asignar una farmacia/laboratorio al item activo
  // ============================================================
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

  // ============================================================
  // NUEVO: Helper para renderizar resultados de busqueda
  // tipoFiltro: 'farmacia' | 'laboratorio' — filtra por farmacia.tipo
  // ============================================================
  const renderResultadosBusqueda = (tipoFiltro: 'farmacia' | 'laboratorio') => {
    // Filtrar por tipo (si el hook retorna farmacia.tipo, sino muestra todo)
    const filtrados = resultadosBusqueda.filter((r: any) => {
      if (!r.farmacia) return false
      // Si no existe el campo tipo, no filtramos (mostramos todo)
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
              <Button
                type="button"
                size="sm"
                className="bg-[#1E5C8E] hover:bg-[#3A8ABF] shrink-0"
                onClick={() => seleccionarProveedor(r)}
              >
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

  // Ver detalle de receta
  const handleViewDetail = (recetaId: number) => {
    navigate(`/recetas/${recetaId}`)
  }

  // Descargar PDF
  const handleDownload = async (recetaId: number) => {
    setPrintingId(recetaId)
    try {
      const { receta, items, paciente } = await getRecetaCompleta(recetaId)
      const medicoPerfil = perfil || {
        nombre_completo: 'Médico',
        email: '',
        telefono: ''
      }

      if (receta && paciente) {
        generarPDFReceta(receta, items, paciente, medicoPerfil)
      } else {
        alert('Error: No se pudieron obtener los datos de la receta')
      }
    } catch (error) {
      console.error('Error descargando PDF:', error)
      alert('Error al descargar PDF: ' + (error as Error).message)
    }
    setPrintingId(null)
  }

  // Imprimir PDF
  const handlePrint = async (recetaId: number) => {
    setPrintingId(recetaId)
    try {
      const { receta, items, paciente } = await getRecetaCompleta(recetaId)
      const medicoPerfil = perfil || {
        nombre_completo: 'Médico',
        email: '',
        telefono: ''
      }

      if (receta && paciente) {
        imprimirPDFReceta(receta, items, paciente, medicoPerfil)
      } else {
        alert('Error: No se pudieron obtener los datos de la receta')
      }
    } catch (error) {
      console.error('Error imprimiendo PDF:', error)
      alert('Error al imprimir PDF: ' + (error as Error).message)
    }
    setPrintingId(null)
  }

  // Enviar receta por email
  const handleEnviarEmail = async (recetaId: number) => {
    const data = await getRecetaCompleta(recetaId)
    if (data.receta) {
      setEmailRecetaData(data)
      setShowEmailModal(true)
    }
  }

  // Cambiar estado
  const handleEstadoChange = async (id: number, estado: string) => {
    await updateReceta(id, { estado: estado as any })
  }

  const getEstadoColor = (estado: string) => {
    switch (estado) {
      case 'activa': return 'bg-green-100 text-green-700 border-green-200'
      case 'completada': return 'bg-blue-100 text-blue-700 border-blue-200'
      case 'vencida': return 'bg-yellow-100 text-yellow-700 border-yellow-200'
      case 'cancelada': return 'bg-red-100 text-red-700 border-red-200'
      default: return 'bg-gray-100 text-gray-700'
    }
  }

  return (
    <div className="p-8 space-y-6">
      {/* Botón Volver al Dashboard */}
      <div className="flex items-center gap-4">
        <Button
          variant="outline"
          size="sm"
          onClick={() => navigate('/dashboard')}
          className="border-[#1E5C8E] text-[#1E5C8E] hover:bg-[#e8f0f8]"
        >
          <ArrowLeft className="h-4 w-4 mr-2" />
          Volver al Dashboard
        </Button>
      </div>

      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a]">Recetas Médicas</h1>
          <p className="text-[#8a9aaa] mt-1">Generación y gestión de recetas médicas digitales</p>
        </div>
        <Button onClick={() => setShowForm(true)} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
          <Plus className="h-4 w-4 mr-2" /> Nueva Receta
        </Button>
      </div>

      {/* Estadísticas rápidas */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {['activa', 'completada', 'vencida', 'cancelada'].map(estado => (
          <Card key={estado} className="border-l-4 border-l-[#1E5C8E]">
            <CardContent className="p-4">
              <p className="text-xs text-[#8a9aaa] uppercase">{estado}s</p>
              <p className="text-2xl font-bold text-[#1a2a3a]">
                {recetas.filter(r => r.estado === estado).length}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card>
        <CardContent className="p-0">
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" /></div>
          ) : recetas.length === 0 ? (
            <div className="text-center py-12 text-[#8a9aaa]">
              <FileText className="h-12 w-12 mx-auto mb-3 opacity-50" />
              <p>No hay recetas registradas</p>
              <p className="text-sm mt-1">Crea tu primera receta médica digital</p>
            </div>
          ) : (
            <div className="divide-y">
              {recetas.map((r) => (
                <div key={r.id} className="p-4 flex items-center justify-between hover:bg-[#e8f0f8] transition-colors">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
  <p className="font-medium truncate">{r.paciente_nombre || 'Paciente #' + r.paciente_id}</p>
  <Badge variant="outline" className={getEstadoColor(r.estado)}>
    {r.estado}
  </Badge>
  {r.tiene_farmacia_asignada && (
    <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200 text-xs">
      <MapPin className="h-3 w-3 mr-1" />
      Farmacia asignada
    </Badge>
  )}
</div>
                    <p className="text-sm text-[#8a9aaa]">
                      {new Date(r.created_at).toLocaleDateString('es-GT', { 
                        weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
                        hour: '2-digit', minute: '2-digit'
                      })}
                    </p>
                  </div>
                  <div className="flex gap-1 ml-4">
                    <Button 
                      variant="ghost" 
                      size="sm" 
                      onClick={() => handleViewDetail(r.id)}
                      title="Ver detalle"
                    >
                      <Eye className="h-4 w-4 text-[#1E5C8E]" />
                    </Button>
                    <Button 
                      variant="ghost" 
                      size="sm" 
                      onClick={() => handleEnviarEmail(r.id)}
                      title="Enviar por email"
                    >
                      <Mail className="h-4 w-4 text-[#3A8ABF]" />
                    </Button>
                    <Button 
                      variant="ghost" 
                      size="sm" 
                      onClick={() => handleDownload(r.id)}
                      disabled={printingId === r.id}
                      title="Descargar PDF"
                    >
                      {printingId === r.id ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : (
                        <Download className="h-4 w-4 text-[#1E5C8E]" />
                      )}
                    </Button>
                    <Button 
                      variant="ghost" 
                      size="sm" 
                      onClick={() => handlePrint(r.id)}
                      disabled={printingId === r.id}
                      title="Imprimir receta"
                    >
                      <Printer className="h-4 w-4 text-[#1E5C8E]" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Dialog: Nueva Receta */}
      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Nueva Receta Médica</DialogTitle>
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
              {/* Alerta de alergias */}
              {form.paciente_id && (() => {
                const paciente = pacientes.find(p => String(p.id) === form.paciente_id)
                if (paciente?.alergias) {
                  return (
                    <div className="bg-red-50 border border-red-200 rounded-lg p-3 flex items-start gap-2">
                      <AlertCircle className="h-4 w-4 text-red-600 shrink-0 mt-0.5" />
                      <div>
                        <p className="text-sm font-medium text-red-700">Alergias del paciente</p>
                        <p className="text-sm text-red-600">{paciente.alergias}</p>
                      </div>
                    </div>
                  )
                }
                return null
              })()}
            </div>

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
                        <div className="space-y-1"><Label className="text-xs">Dosis *</Label><Input className="h-8 text-sm" value={item.dosis} onChange={e => updateItem(idx, 'dosis', e.target.value)} placeholder="500mg" required /></div>
                        <div className="space-y-1"><Label className="text-xs">Frecuencia *</Label><Input className="h-8 text-sm" value={item.frecuencia} onChange={e => updateItem(idx, 'frecuencia', e.target.value)} placeholder="Cada 8 horas" required /></div>
                        <div className="space-y-1"><Label className="text-xs">Duración</Label><Input className="h-8 text-sm" value={item.duracion || ''} onChange={e => updateItem(idx, 'duracion', e.target.value)} placeholder="7 días" /></div>
                        <div className="space-y-1"><Label className="text-xs">Cantidad</Label><Input type="number" className="h-8 text-sm" value={item.cantidad} onChange={e => updateItem(idx, 'cantidad', parseInt(e.target.value) || 1)} min={1} /></div>
                      </div>
                      <div className="space-y-1"><Label className="text-xs">Instrucciones especiales</Label><Input className="h-8 text-sm" value={item.instrucciones || ''} onChange={e => updateItem(idx, 'instrucciones', e.target.value)} placeholder="Tomar después de las comidas" /></div>

                      {/* ============================================ */}
                      {/* NUEVO: Botones Farmacia / Laboratorio */}
                      {/* ============================================ */}
                      <div className="flex items-center gap-2 pt-2 border-t border-[#1E5C8E]/10">
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          onClick={() => abrirModalFarmacia(idx)}
                          className={item.farmacia_id ? 'border-green-500 text-green-700 hover:bg-green-50' : 'border-[#1E5C8E] text-[#1E5C8E] hover:bg-white'}
                        >
                          {item.farmacia_id ? (
                            <CheckCircle2 className="h-3 w-3 mr-1" />
                          ) : (
                            <MapPin className="h-3 w-3 mr-1" />
                          )}
                          Farmacias
                        </Button>
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          onClick={() => abrirModalLaboratorio(idx)}
                          className="border-[#3A8ABF] text-[#3A8ABF] hover:bg-white"
                        >
                          <FlaskConical className="h-3 w-3 mr-1" />
                          Laboratorios
                        </Button>
                        {item.farmacia_id && (
                          <span className="text-xs text-green-700 ml-1">
                            ✓ Proveedor asignado (#{item.farmacia_id})
                          </span>
                        )}
                      </div>
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
              <Button type="button" variant="outline" onClick={() => { setShowForm(false); setFormError(''); setItems([]) }}>Cancelar</Button>
              <Button type="submit" className="bg-[#1E5C8E] hover:bg-[#3A8ABF]" disabled={saving || items.length === 0}>
                {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Generar Receta
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Dialog: Ver Detalle de Receta */}
      <Dialog open={showDetail} onOpenChange={setShowDetail}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center justify-between">
              <span>Detalle de Receta</span>
              {selectedReceta?.receta && (
                <Badge variant="outline" className={getEstadoColor(selectedReceta.receta.estado)}>
                  {selectedReceta.receta.estado}
                </Badge>
              )}
            </DialogTitle>
          </DialogHeader>

          {selectedReceta && (
            <div className="space-y-6">
              {/* Info Paciente */}
              <Card className="bg-[#e8f0f8]">
                <CardHeader>
                  <CardTitle className="text-base text-[#1E5C8E]">Paciente</CardTitle>
                </CardHeader>
                <CardContent className="space-y-2">
                  <p className="font-medium">{selectedReceta.paciente?.nombre} {selectedReceta.paciente?.apellido}</p>
                  <p className="text-sm text-[#8a9aaa]">Tel: {selectedReceta.paciente?.telefono || 'N/A'}</p>
                  <p className="text-sm text-[#8a9aaa]">Alergias: {selectedReceta.paciente?.alergias || 'Ninguna'}</p>
                </CardContent>
              </Card>

              {/* Medicamentos */}
              <div className="space-y-3">
                <h3 className="font-medium text-[#1a2a3a]">Medicamentos Prescritos ({selectedReceta.items.length})</h3>
                {selectedReceta.items.map((item: any, idx: number) => (
                  <Card key={item.id} className="border-l-4 border-l-[#1E5C8E]">
                    <CardContent className="p-4">
                      <div className="flex justify-between items-start">
                        <div>
                          <p className="font-medium text-[#1E5C8E]">{idx + 1}. {item.nombre_medicamento}</p>
                          <div className="grid grid-cols-2 gap-x-6 gap-y-1 mt-2 text-sm">
                            <p><span className="text-[#8a9aaa]">Dosis:</span> {item.dosis}</p>
                            <p><span className="text-[#8a9aaa]">Frecuencia:</span> {item.frecuencia}</p>
                            <p><span className="text-[#8a9aaa]">Duración:</span> {item.duracion || 'N/A'}</p>
                            <p><span className="text-[#8a9aaa]">Cantidad:</span> {item.cantidad}</p>
                          </div>
                          {item.instrucciones && (
                            <p className="text-sm mt-2 text-[#8a9aaa]">Instrucciones: {item.instrucciones}</p>
                          )}
                         {item.farmacia_id && item.farmacia && (
  <p className="text-sm mt-2 text-green-700">
    <CheckCircle2 className="h-3 w-3 inline mr-1" />
    Farmacia asignada: <strong>{item.farmacia.nombre}</strong>
    {item.farmacia.direccion && (
      <span className="text-xs text-[#8a9aaa] ml-1">({item.farmacia.direccion})</span>
    )}
  </p>
)}
{item.farmacia_id && !item.farmacia && (
  <p className="text-sm mt-2 text-green-700">
    <CheckCircle2 className="h-3 w-3 inline mr-1" />
    Proveedor asignado (Farmacia #{item.farmacia_id})
  </p>
)}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>

              {/* Instrucciones generales */}
              {selectedReceta.receta?.instrucciones_generales && (
                <Card>
                  <CardHeader>
                    <CardTitle className="text-base">Instrucciones Generales</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="text-sm">{selectedReceta.receta.instrucciones_generales}</p>
                  </CardContent>
                </Card>
              )}

              {/* Fecha */}
              <p className="text-xs text-[#8a9aaa] text-center">
                Receta emitida el {new Date(selectedReceta.receta.created_at).toLocaleDateString('es-GT', {
                  weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
                  hour: '2-digit', minute: '2-digit'
                })}
              </p>

              {/* Botones */}
              <div className="flex gap-3 justify-end">
                <Button variant="outline" onClick={() => setShowDetail(false)}>
                  <X className="h-4 w-4 mr-2" /> Cerrar
                </Button>
                <Button 
                  variant="outline"
                  className="border-[#3A8ABF] text-[#3A8ABF] hover:bg-[#e8f0f8]"
                  onClick={() => {
                    setShowDetail(false)
                    handleEnviarEmail(selectedReceta.receta.id)
                  }}
                >
                  <Mail className="h-4 w-4 mr-2" /> Enviar por Email
                </Button>
                <Button 
                  variant="outline"
                  className="border-[#1E5C8E] text-[#1E5C8E] hover:bg-[#e8f0f8]"
                  onClick={() => {
                    try {
                      const medicoPerfil = perfil || {
                        nombre_completo: 'Médico',
                        email: '',
                        telefono: ''
                      }
                      if (selectedReceta.receta && selectedReceta.paciente) {
                       console.log('Items para PDF:', selectedReceta.items) 
                       generarPDFReceta(selectedReceta.receta, selectedReceta.items, selectedReceta.paciente, medicoPerfil)
                      } else {
                        alert('Faltan datos para generar el PDF')
                      }
                    } catch (error) {
                      console.error('Error descargando PDF:', error)
                      alert('Error al descargar PDF: ' + (error as Error).message)
                    }
                  }}
                >
                  <Download className="h-4 w-4 mr-2" /> Descargar PDF
                </Button>
                <Button 
                  className="bg-[#1E5C8E] hover:bg-[#3A8ABF]"
                  onClick={() => {
                    try {
                      const medicoPerfil = perfil || {
                        nombre_completo: 'Médico',
                        email: '',
                        telefono: ''
                      }
                      if (selectedReceta.receta && selectedReceta.paciente) {
                        imprimirPDFReceta(selectedReceta.receta, selectedReceta.items, selectedReceta.paciente, medicoPerfil)
                      } else {
                        alert('Faltan datos para imprimir')
                      }
                    } catch (error) {
                      console.error('Error imprimiendo PDF:', error)
                      alert('Error al imprimir: ' + (error as Error).message)
                    }
                  }}
                >
                  <Printer className="h-4 w-4 mr-2" /> Imprimir
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Modal de enviar receta por email */}
      <EnviarRecetaEmail
        open={showEmailModal}
        onOpenChange={setShowEmailModal}
        receta={emailRecetaData?.receta || null}
        medicamentos={emailRecetaData?.items || []}
        medicoNombre={perfil?.nombre_completo}
      />

      {/* ============================================================ */}
      {/* NUEVO: Modal de busqueda de FARMACIAS */}
      {/* ============================================================ */}
      <Dialog open={showFarmaciaModal} onOpenChange={setShowFarmaciaModal}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MapPin className="h-5 w-5 text-[#1E5C8E]" />
              Seleccionar Farmacia
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            {itemIdxBuscando !== null && items[itemIdxBuscando] && (
              <div className="bg-[#e8f0f8] p-3 rounded-md">
                <p className="text-xs text-[#8a9aaa]">Medicamento:</p>
                <p className="font-medium text-[#1E5C8E]">{items[itemIdxBuscando].nombre_medicamento}</p>
              </div>
            )}

            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
              <Input
                placeholder="Buscar medicamento en farmacias..."
                value={busquedaProveedor}
                onChange={(e) => {
                  setBusquedaProveedor(e.target.value)
                  buscarEnProveedor(e.target.value)
                }}
                className="pl-10"
              />
            </div>

            {renderResultadosBusqueda('farmacia')}

            <div className="flex justify-end pt-2 border-t">
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setShowFarmaciaModal(false)
                  setItemIdxBuscando(null)
                  setBusquedaProveedor('')
                }}
              >
                <X className="h-4 w-4 mr-2" /> Cancelar
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* ============================================================ */}
      {/* NUEVO: Modal de busqueda de LABORATORIOS */}
      {/* ============================================================ */}
      <Dialog open={showLaboratorioModal} onOpenChange={setShowLaboratorioModal}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <FlaskConical className="h-5 w-5 text-[#3A8ABF]" />
              Seleccionar Laboratorio
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            {itemIdxBuscando !== null && items[itemIdxBuscando] && (
              <div className="bg-[#e8f0f8] p-3 rounded-md">
                <p className="text-xs text-[#8a9aaa]">Medicamento:</p>
                <p className="font-medium text-[#3A8ABF]">{items[itemIdxBuscando].nombre_medicamento}</p>
              </div>
            )}

            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
              <Input
                placeholder="Buscar medicamento en laboratorios..."
                value={busquedaProveedor}
                onChange={(e) => {
                  setBusquedaProveedor(e.target.value)
                  buscarEnProveedor(e.target.value)
                }}
                className="pl-10"
              />
            </div>

            {renderResultadosBusqueda('laboratorio')}

            <div className="flex justify-end pt-2 border-t">
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setShowLaboratorioModal(false)
                  setItemIdxBuscando(null)
                  setBusquedaProveedor('')
                }}
              >
                <X className="h-4 w-4 mr-2" /> Cancelar
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
