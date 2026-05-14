import { useState, useEffect } from 'react'
import { useAuth } from '@/hooks/useAuth'
import { useConfiguracion } from '@/hooks/useConfiguracion'
import { useClinicas } from '@/hooks/useClinicas'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { 
  Settings, User, Shield, Download, Clock, DollarSign, 
  CreditCard, Bell, Building2, Stethoscope, Save, Check, 
  Loader2, Plus, Trash2, Edit3, MapPin, Phone, Mail, CheckCircle 
} from 'lucide-react'

const DIAS_SEMANA = [
  { key: 'lunes', label: 'Lunes' },
  { key: 'martes', label: 'Martes' },
  { key: 'miercoles', label: 'Miércoles' },
  { key: 'jueves', label: 'Jueves' },
  { key: 'viernes', label: 'Viernes' },
  { key: 'sabado', label: 'Sábado' },
  { key: 'domingo', label: 'Domingo' },
]

const defaultHorarios = {
  lunes: { activo: true, inicio: '08:00', fin: '17:00' },
  martes: { activo: true, inicio: '08:00', fin: '17:00' },
  miercoles: { activo: true, inicio: '08:00', fin: '17:00' },
  jueves: { activo: true, inicio: '08:00', fin: '17:00' },
  viernes: { activo: true, inicio: '08:00', fin: '17:00' },
  sabado: { activo: false, inicio: '08:00', fin: '12:00' },
  domingo: { activo: false, inicio: '08:00', fin: '12:00' },
}

export default function ConfiguracionPage() {
  const { perfil, logout } = useAuth()
  const { config, loading: loadingConfig, guardarConfig } = useConfiguracion()
  const { clinicas, loading: loadingClinicas, crearClinica, actualizarClinica, eliminarClinica, setClinicaActiva } = useClinicas()

  const [guardado, setGuardado] = useState(false)
  const [activeTab, setActiveTab] = useState('perfil')
  const [localError, setLocalError] = useState('')

  // Modal de clínica
  const [showClinicaModal, setShowClinicaModal] = useState(false)
  const [editingClinica, setEditingClinica] = useState<any>(null)
  const [clinicaForm, setClinicaForm] = useState({
    nombre: '',
    direccion: '',
    telefono: '',
    email: '',
    horarios: { ...defaultHorarios }
  })

  const loading = loadingConfig || loadingClinicas

  // Sincronizar con perfil
  useEffect(() => {
    if (perfil) {
      // Esto se maneja en useConfiguracion
    }
  }, [perfil])

  const updateConfig = (field: string, value: any) => {
    // Esto se maneja en useConfiguracion
  }

  const handleGuardar = async () => {
    setLocalError('')
    const result = await guardarConfig(config)
    if (result.success) {
      setGuardado(true)
      setTimeout(() => setGuardado(false), 3000)
    } else {
      setLocalError(result.error || 'Error al guardar')
    }
  }

  const openClinicaModal = (clinica?: any) => {
    if (clinica) {
      setEditingClinica(clinica)
      setClinicaForm({
        nombre: clinica.nombre,
        direccion: clinica.direccion,
        telefono: clinica.telefono,
        email: clinica.email,
        horarios: { ...defaultHorarios, ...clinica.horarios }
      })
    } else {
      setEditingClinica(null)
      setClinicaForm({
        nombre: '',
        direccion: '',
        telefono: '',
        email: '',
        horarios: { ...defaultHorarios }
      })
    }
    setShowClinicaModal(true)
  }

  const handleSaveClinica = async () => {
    if (!clinicaForm.nombre.trim()) {
      setLocalError('El nombre de la clínica es obligatorio')
      return
    }

    if (editingClinica) {
      await actualizarClinica(editingClinica.id, {
        ...clinicaForm,
        horarios: clinicaForm.horarios
      })
    } else {
      await crearClinica({
        ...clinicaForm,
        horarios: clinicaForm.horarios
      })
    }

    setShowClinicaModal(false)
    setEditingClinica(null)
    setGuardado(true)
    setTimeout(() => setGuardado(false), 3000)
  }

  const handleDeleteClinica = async (id: string) => {
    if (confirm('¿Estás seguro de eliminar esta clínica?')) {
      await eliminarClinica(id)
    }
  }

  const updateClinicaHorario = (dia: string, field: string, value: any) => {
    setClinicaForm(prev => ({
      ...prev,
      horarios: {
        ...prev.horarios,
        [dia]: { ...prev.horarios[dia], [field]: value }
      }
    }))
  }

  const exportarDatos = () => {
    const data = {
      config,
      clinicas,
      exportado: new Date().toISOString(),
      version: '2.0'
    }
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `ezpayconnect-config-${new Date().toISOString().split('T')[0]}.json`
    a.click()
  }

  const tabs = [
    { id: 'perfil', label: 'Perfil', icon: User },
    { id: 'clinicas', label: 'Mis Clínicas', icon: Building2 },
    { id: 'precios', label: 'Precios', icon: DollarSign },
    { id: 'pagos', label: 'Pagos', icon: CreditCard },
    { id: 'notificaciones', label: 'Notificaciones', icon: Bell },
  ]

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-12 w-12 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a] flex items-center gap-2">
            <Settings className="h-8 w-8 text-[#1E5C8E]" />
            Configuración
          </h1>
          <p className="text-[#8a9aaa] mt-1">Personaliza tu consultorio médico</p>
        </div>
        <div className="flex items-center gap-3">
          {guardado && (
            <div className="flex items-center gap-2 text-green-600 bg-green-50 px-3 py-2 rounded-lg">
              <Check className="h-4 w-4" />
              <span className="text-sm font-medium">Guardado en Supabase</span>
            </div>
          )}
          <Button onClick={handleGuardar} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
            <Save className="h-4 w-4 mr-2" /> Guardar Cambios
          </Button>
        </div>
      </div>

      {localError && (
        <div className="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded-lg">
          {localError}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {tabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all ${
              activeTab === tab.id
                ? 'bg-[#1E5C8E] text-white shadow-sm'
                : 'bg-[#e8f0f8] text-[#8a9aaa] hover:text-[#1a2a3a]'
            }`}
          >
            <tab.icon className="h-4 w-4" />
            {tab.label}
          </button>
        ))}
      </div>

      <div className="space-y-6">
        {/* ========== PERFIL DEL DOCTOR ========== */}
        {activeTab === 'perfil' && (
          <Card>
            <CardHeader className="flex flex-row items-center gap-3">
              <Stethoscope className="h-6 w-6 text-[#1E5C8E]" />
              <CardTitle className="text-lg">Perfil del Doctor</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-2">
                <Label>Nombre Completo *</Label>
                <Input 
                  value={config.nombre_completo} 
                  readOnly
                  className="bg-[#f8fafc]"
                />
                <p className="text-xs text-[#8a9aaa]">Se actualiza desde tu perfil de usuario</p>
              </div>
              <div className="space-y-2">
                <Label>Especialidad *</Label>
                <Select value={config.especialidad} onValueChange={v => {/* handled by hook */}}>
                  <SelectTrigger><SelectValue placeholder="Seleccionar especialidad" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="medicina_general">Medicina General</SelectItem>
                    <SelectItem value="pediatria">Pediatría</SelectItem>
                    <SelectItem value="cardiologia">Cardiología</SelectItem>
                    <SelectItem value="dermatologia">Dermatología</SelectItem>
                    <SelectItem value="ginecologia">Ginecología</SelectItem>
                    <SelectItem value="ortopedia">Ortopedia</SelectItem>
                    <SelectItem value="neurologia">Neurología</SelectItem>
                    <SelectItem value="psiquiatria">Psiquiatría</SelectItem>
                    <SelectItem value="otra">Otra</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Cédula Profesional</Label>
                <Input 
                  value={config.cedula} 
                  placeholder="12345678"
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
              <div className="space-y-2">
                <Label>Teléfono</Label>
                <Input 
                  value={config.telefono} 
                  placeholder="+502 1234 5678"
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
              <div className="space-y-2 md:col-span-2">
                <Label>Correo Electrónico</Label>
                <Input 
                  value={config.email} 
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
            </CardContent>
          </Card>
        )}

        {/* ========== MIS CLÍNICAS ========== */}
        {activeTab === 'clinicas' && (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <h2 className="text-xl font-bold text-[#1a2a3a] flex items-center gap-2">
                <Building2 className="h-6 w-6 text-[#1E5C8E]" />
                Mis Clínicas
              </h2>
              <Button onClick={() => openClinicaModal()} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
                <Plus className="h-4 w-4 mr-2" /> Nueva Clínica
              </Button>
            </div>

            {clinicas.length === 0 ? (
              <Card className="bg-[#f8fafc]">
                <CardContent className="p-12 text-center">
                  <Building2 className="h-12 w-12 mx-auto mb-4 text-[#8a9aaa]" />
                  <p className="text-[#8a9aaa] mb-4">No tienes clínicas registradas</p>
                  <Button onClick={() => openClinicaModal()} variant="outline">
                    <Plus className="h-4 w-4 mr-2" /> Agregar primera clínica
                  </Button>
                </CardContent>
              </Card>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {clinicas.map(clinica => (
                  <Card key={clinica.id} className={`border-l-4 ${clinica.activa ? 'border-l-[#22c55e]' : 'border-l-[#8a9aaa]'}`}>
                    <CardContent className="p-6">
                      <div className="flex items-start justify-between mb-4">
                        <div>
                          <h3 className="font-bold text-[#1a2a3a] text-lg">{clinica.nombre}</h3>
                          {clinica.activa && (
                            <span className="inline-flex items-center gap-1 text-xs text-green-600 bg-green-50 px-2 py-1 rounded-full mt-1">
                              <CheckCircle className="h-3 w-3" /> Activa
                            </span>
                          )}
                        </div>
                        <div className="flex gap-1">
                          <Button variant="ghost" size="sm" onClick={() => openClinicaModal(clinica)}>
                            <Edit3 className="h-4 w-4 text-[#1E5C8E]" />
                          </Button>
                          <Button variant="ghost" size="sm" onClick={() => handleDeleteClinica(clinica.id)}>
                            <Trash2 className="h-4 w-4 text-red-500" />
                          </Button>
                        </div>
                      </div>

                      <div className="space-y-2 text-sm">
                        {clinica.direccion && (
                          <div className="flex items-center gap-2 text-[#8a9aaa]">
                            <MapPin className="h-4 w-4" />
                            {clinica.direccion}
                          </div>
                        )}
                        {clinica.telefono && (
                          <div className="flex items-center gap-2 text-[#8a9aaa]">
                            <Phone className="h-4 w-4" />
                            {clinica.telefono}
                          </div>
                        )}
                        {clinica.email && (
                          <div className="flex items-center gap-2 text-[#8a9aaa]">
                            <Mail className="h-4 w-4" />
                            {clinica.email}
                          </div>
                        )}
                      </div>

                      {!clinica.activa && (
                        <Button 
                          variant="outline" 
                          size="sm" 
                          className="w-full mt-4"
                          onClick={() => setClinicaActiva(clinica.id)}
                        >
                          <CheckCircle className="h-4 w-4 mr-2" /> Activar esta clínica
                        </Button>
                      )}
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>
        )}

        {/* ========== PRECIOS ========== */}
        {activeTab === 'precios' && (
          <Card>
            <CardHeader className="flex flex-row items-center gap-3">
              <DollarSign className="h-6 w-6 text-[#1E5C8E]" />
              <CardTitle className="text-lg">Precios de Servicios (Q)</CardTitle>
            </CardHeader>
            <CardContent className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-2">
                <Label>Consulta General</Label>
                <Input 
                  type="number" 
                  value={config.precios?.consulta_general || 150} 
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
              <div className="space-y-2">
                <Label>Consulta Especialidad</Label>
                <Input 
                  type="number" 
                  value={config.precios?.consulta_especialidad || 250} 
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
              <div className="space-y-2">
                <Label>Receta Médica</Label>
                <Input 
                  type="number" 
                  value={config.precios?.receta || 50} 
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
              <div className="space-y-2">
                <Label>Exámen Básico</Label>
                <Input 
                  type="number" 
                  value={config.precios?.examen_basico || 100} 
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
              <div className="space-y-2 md:col-span-2">
                <Label>Exámen Completo</Label>
                <Input 
                  type="number" 
                  value={config.precios?.examen_completo || 300} 
                  readOnly
                  className="bg-[#f8fafc]"
                />
              </div>
            </CardContent>
          </Card>
        )}

        {/* ========== MÉTODOS DE PAGO ========== */}
        {activeTab === 'pagos' && (
          <Card>
            <CardHeader className="flex flex-row items-center gap-3">
              <CreditCard className="h-6 w-6 text-[#1E5C8E]" />
              <CardTitle className="text-lg">Métodos de Pago Aceptados</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {[
                  { key: 'efectivo', label: 'Efectivo', icon: DollarSign },
                  { key: 'tarjeta', label: 'Tarjeta de Crédito/Débito', icon: CreditCard },
                  { key: 'transferencia', label: 'Transferencia Bancaria', icon: Download },
                  { key: 'seguro', label: 'Seguro Médico', icon: Shield },
                  { key: 'cheque', label: 'Cheque', icon: CreditCard },
                ].map(({ key, label, icon: Icon }) => (
                  <div key={key} className="flex items-center justify-between p-4 bg-[#f8fafc] rounded-lg">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-lg bg-[#e8f0f8] flex items-center justify-center">
                        <Icon className="h-5 w-5 text-[#1E5C8E]" />
                      </div>
                      <span className="font-medium text-[#1a2a3a]">{label}</span>
                    </div>
                    <Switch 
                      checked={config.metodos_pago?.[key] || false} 
                      disabled
                    />
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {/* ========== NOTIFICACIONES ========== */}
        {activeTab === 'notificaciones' && (
          <Card>
            <CardHeader className="flex flex-row items-center gap-3">
              <Bell className="h-6 w-6 text-[#1E5C8E]" />
              <CardTitle className="text-lg">Notificaciones Automáticas</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {[
                { key: 'email', label: 'Recordatorio por Email', desc: 'Enviar recordatorio de cita al paciente por correo' },
                { key: 'sms', label: 'Recordatorio por SMS', desc: 'Enviar mensaje de texto al teléfono del paciente' },
                { key: 'recordatorio_24h', label: 'Recordatorio 24h antes', desc: 'Notificar al paciente un día antes de su cita' },
                { key: 'recordatorio_2h', label: 'Recordatorio 2h antes', desc: 'Notificar al paciente 2 horas antes de su cita' },
                { key: 'confirmacion_automatica', label: 'Confirmación Automática', desc: 'Confirmar citas automáticamente al recibir respuesta del paciente' },
              ].map(({ key, label, desc }) => (
                <div key={key} className="flex items-center justify-between p-4 bg-[#f8fafc] rounded-lg">
                  <div>
                    <p className="font-medium text-[#1a2a3a]">{label}</p>
                    <p className="text-sm text-[#8a9aaa]">{desc}</p>
                  </div>
                  <Switch 
                    checked={config.notificaciones?.[key] || false} 
                    disabled
                  />
                </div>
              ))}
            </CardContent>
          </Card>
        )}
      </div>

      {/* Footer */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-4">
        <Card>
          <CardHeader className="flex flex-row items-center gap-3">
            <Download className="h-6 w-6 text-[#1E5C8E]" />
            <CardTitle className="text-lg">Exportar Configuración</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-[#8a9aaa] mb-4">
              Descarga tu configuración completa como respaldo JSON.
            </p>
            <Button variant="outline" className="w-full" onClick={exportarDatos}>
              <Download className="h-4 w-4 mr-2" /> Exportar JSON
            </Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center gap-3">
            <Settings className="h-6 w-6 text-red-500" />
            <CardTitle className="text-lg text-red-500">Cerrar Sesión</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-[#8a9aaa] mb-4">
              Cierra tu sesión de forma segura.
            </p>
            <Button variant="destructive" className="w-full" onClick={logout}>
              Cerrar Sesión
            </Button>
          </CardContent>
        </Card>
      </div>

      {/* Modal de Clínica */}
      <Dialog open={showClinicaModal} onOpenChange={setShowClinicaModal}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Building2 className="h-5 w-5 text-[#1E5C8E]" />
              {editingClinica ? 'Editar Clínica' : 'Nueva Clínica'}
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-2 md:col-span-2">
                <Label>Nombre de la Clínica *</Label>
                <Input 
                  value={clinicaForm.nombre}
                  onChange={e => setClinicaForm(prev => ({ ...prev, nombre: e.target.value }))}
                  placeholder="Clínica San Rafael"
                />
              </div>
              <div className="space-y-2 md:col-span-2">
                <Label>Dirección</Label>
                <Textarea 
                  value={clinicaForm.direccion}
                  onChange={e => setClinicaForm(prev => ({ ...prev, direccion: e.target.value }))}
                  placeholder="Av. Reforma 12-34, Zona 9, Ciudad de Guatemala"
                  rows={2}
                />
              </div>
              <div className="space-y-2">
                <Label>Teléfono</Label>
                <Input 
                  value={clinicaForm.telefono}
                  onChange={e => setClinicaForm(prev => ({ ...prev, telefono: e.target.value }))}
                  placeholder="+502 8765 4321"
                />
              </div>
              <div className="space-y-2">
                <Label>Email</Label>
                <Input 
                  value={clinicaForm.email}
                  onChange={e => setClinicaForm(prev => ({ ...prev, email: e.target.value }))}
                  placeholder="info@clinica.com"
                  type="email"
                />
              </div>
            </div>

            <div>
              <h4 className="font-medium text-[#1a2a3a] mb-3">Horarios de Atención</h4>
              <div className="space-y-3">
                {DIAS_SEMANA.map(({ key, label }) => {
                  const horario = clinicaForm.horarios[key] || { activo: false, inicio: '08:00', fin: '17:00' }
                  return (
                    <div key={key} className="flex items-center gap-3 p-3 bg-[#f8fafc] rounded-lg">
                      <Switch 
                        checked={horario.activo} 
                        onCheckedChange={v => updateClinicaHorario(key, 'activo', v)}
                      />
                      <span className={`min-w-[80px] font-medium ${horario.activo ? 'text-[#1a2a3a]' : 'text-[#8a9aaa]'}`}>
                        {label}
                      </span>
                      <Input 
                        type="time" 
                        value={horario.inicio}
                        onChange={e => updateClinicaHorario(key, 'inicio', e.target.value)}
                        disabled={!horario.activo}
                        className="w-28"
                      />
                      <span className="text-[#8a9aaa]">a</span>
                      <Input 
                        type="time" 
                        value={horario.fin}
                        onChange={e => updateClinicaHorario(key, 'fin', e.target.value)}
                        disabled={!horario.activo}
                        className="w-28"
                      />
                    </div>
                  )
                })}
              </div>
            </div>

            <div className="flex justify-end gap-3">
              <Button variant="outline" onClick={() => setShowClinicaModal(false)}>
                Cancelar
              </Button>
              <Button onClick={handleSaveClinica} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
                <Save className="h-4 w-4 mr-2" />
                {editingClinica ? 'Guardar Cambios' : 'Crear Clínica'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}