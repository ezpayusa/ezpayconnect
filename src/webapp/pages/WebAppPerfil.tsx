import { useState } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { usePushNotifications } from '@/webapp/hooks/usePushNotifications'
import { supabase } from '@/lib/supabase'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  User, Mail, Phone, Calendar, AlertTriangle, MapPin, Heart, Users,
  Pencil, Save, X, Loader2, Bell, BellOff
} from 'lucide-react'
import { toast } from 'sonner'

// Componente de campo de formulario (definido FUERA para evitar re-renders)
function CampoPerfil({ icon: Icon, label, value, editando, editValue, onChange, type = 'text' }: any) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs text-slate-500 flex items-center gap-1.5">
        <Icon className="h-3.5 w-3.5" />
        {label}
      </Label>
      {editando ? (
        <Input
          type={type}
          value={editValue}
          onChange={(e) => onChange?.(e.target.value)}
          className="h-9 text-sm"
        />
      ) : (
        <p className="text-sm text-slate-700">{value || 'No registrado'}</p>
      )}
    </div>
  )
}

export default function WebAppPerfil() {
  const { perfil } = useWebAppAuth()
  const {
    soportado: pushSoportado,
    suscrito: pushSuscrito,
    permiso: pushPermiso,
    suscribir: suscribirPush,
    desuscribir: desuscribirPush,
    cargando: pushCargando,
  } = usePushNotifications()
  const [editando, setEditando] = useState(false)
  const [guardando, setGuardando] = useState(false)
  const [form, setForm] = useState({
    nombre: perfil?.nombre || '',
    apellido: perfil?.apellido || '',
    telefono: perfil?.telefono || '',
    fecha_nacimiento: perfil?.fecha_nacimiento || '',
    genero: perfil?.genero || '',
    direccion: perfil?.direccion || '',
    alergias: perfil?.alergias || '',
    notas: perfil?.notas || '',
    emergencia_nombre: perfil?.emergencia_nombre || '',
    emergencia_telefono: perfil?.emergencia_telefono || '',
  })

  const handleGuardar = async () => {
    if (!perfil?.id) return
    try {
      setGuardando(true)
      const { error } = await supabase
        .from('pacientes')
        .update({
          nombre: form.nombre,
          apellido: form.apellido,
          telefono: form.telefono || null,
          fecha_nacimiento: form.fecha_nacimiento || null,
          genero: form.genero || null,
          direccion: form.direccion || null,
          alergias: form.alergias || null,
          notas: form.notas || null,
          emergencia_nombre: form.emergencia_nombre || null,
          emergencia_telefono: form.emergencia_telefono || null,
        })
        .eq('id', perfil.id)

      if (error) throw error
      toast.success('Perfil actualizado correctamente')
      setEditando(false)
      window.location.reload()
    } catch (err: any) {
      toast.error('Error al guardar: ' + err.message)
    } finally {
      setGuardando(false)
    }
  }

  const handleCancelar = () => {
    setForm({
      nombre: perfil?.nombre || '',
      apellido: perfil?.apellido || '',
      telefono: perfil?.telefono || '',
      fecha_nacimiento: perfil?.fecha_nacimiento || '',
      genero: perfil?.genero || '',
      direccion: perfil?.direccion || '',
      alergias: perfil?.alergias || '',
      notas: perfil?.notas || '',
      emergencia_nombre: perfil?.emergencia_nombre || '',
      emergencia_telefono: perfil?.emergencia_telefono || '',
    })
    setEditando(false)
  }

  return (
    <div className="space-y-6 max-w-2xl">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">Mi Perfil</h1>
          <p className="text-slate-500 mt-1">Tus datos personales y médicos</p>
        </div>
        {editando ? (
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={handleCancelar}>
              <X className="h-4 w-4 mr-1" /> Cancelar
            </Button>
            <Button size="sm" onClick={handleGuardar} disabled={guardando}>
              {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Save className="h-4 w-4 mr-1" />}
              Guardar
            </Button>
          </div>
        ) : (
          <Button variant="outline" size="sm" onClick={() => setEditando(true)}>
            <Pencil className="h-4 w-4 mr-1" /> Editar
          </Button>
        )}
      </div>

      <Card className="bg-white border-slate-100">
        <CardContent className="p-6">
          <div className="flex items-center gap-4 mb-6">
            <div className="w-16 h-16 rounded-full bg-gradient-to-br from-sky-500 to-indigo-500 flex items-center justify-center text-white font-bold text-xl">
              {perfil ? `${perfil.nombre?.charAt(0)}${perfil.apellido?.charAt(0)}` : '?'}
            </div>
            <div>
              <h2 className="text-lg font-semibold text-slate-800">
                {perfil ? `${perfil.nombre} ${perfil.apellido}` : 'Paciente'}
              </h2>
              <p className="text-sm text-slate-500">Paciente</p>
            </div>
          </div>

          <div className="space-y-5">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <CampoPerfil
                icon={User}
                label="Nombre"
                value={perfil?.nombre}
                editando={editando}
                editValue={form.nombre}
                onChange={(v: string) => setForm({ ...form, nombre: v })}
              />
              <CampoPerfil
                icon={User}
                label="Apellido"
                value={perfil?.apellido}
                editando={editando}
                editValue={form.apellido}
                onChange={(v: string) => setForm({ ...form, apellido: v })}
              />
              <CampoPerfil
                icon={Mail}
                label="Email"
                value={perfil?.email}
                editando={editando}
                editValue={perfil?.email || ''}
              />
              <CampoPerfil
                icon={Phone}
                label="Teléfono"
                value={perfil?.telefono}
                editando={editando}
                editValue={form.telefono}
                onChange={(v: string) => setForm({ ...form, telefono: v })}
              />
              <CampoPerfil
                icon={Calendar}
                label="Fecha de nacimiento"
                value={perfil?.fecha_nacimiento ? new Date(perfil.fecha_nacimiento).toLocaleDateString('es-GT') : ''}
                editando={editando}
                editValue={form.fecha_nacimiento}
                onChange={(v: string) => setForm({ ...form, fecha_nacimiento: v })}
                type="date"
              />
              <CampoPerfil
                icon={User}
                label="Género"
                value={perfil?.genero}
                editando={editando}
                editValue={form.genero}
                onChange={(v: string) => setForm({ ...form, genero: v })}
              />
            </div>

            <CampoPerfil
              icon={MapPin}
              label="Dirección"
              value={perfil?.direccion}
              editando={editando}
              editValue={form.direccion}
              onChange={(v: string) => setForm({ ...form, direccion: v })}
            />

            {perfil?.alergias && !editando ? (
              <div className="flex items-start gap-3 text-amber-600 bg-amber-50 p-3 rounded-lg">
                <AlertTriangle className="h-4 w-4 mt-0.5" />
                <div>
                  <p className="font-medium text-sm">Alergias</p>
                  <p className="text-sm">{perfil.alergias}</p>
                </div>
              </div>
            ) : (
              <CampoPerfil
                icon={AlertTriangle}
                label="Alergias"
                value={perfil?.alergias}
                editando={editando}
                editValue={form.alergias}
                onChange={(v: string) => setForm({ ...form, alergias: v })}
              />
            )}

            <CampoPerfil
              icon={Heart}
              label="Notas médicas"
              value={perfil?.notas}
              editando={editando}
              editValue={form.notas}
              onChange={(v: string) => setForm({ ...form, notas: v })}
            />

            {/* Notificaciones push */}
            <div className="border-t border-slate-100 pt-4">
              <h3 className="text-sm font-medium text-slate-700 mb-3 flex items-center gap-1.5">
                <Bell className="h-4 w-4" />
                Notificaciones push
              </h3>
              {pushSoportado && pushPermiso !== 'denied' && (
                <div className={`flex items-center justify-between p-3 rounded-lg ${pushSuscrito ? 'bg-emerald-50' : 'bg-amber-50'}`}>
                  <div className="flex items-center gap-3">
                    {pushSuscrito ? (
                      <Bell className="h-4 w-4 text-emerald-600" />
                    ) : (
                      <BellOff className="h-4 w-4 text-amber-600" />
                    )}
                    <div>
                      <p className="text-sm font-medium text-slate-700">
                        {pushSuscrito ? 'Activadas' : 'Desactivadas'}
                      </p>
                      <p className="text-xs text-slate-500">
                        {pushSuscrito
                          ? 'Recibes alertas de citas y mensajes en tiempo real'
                          : 'Activa para recibir alertas de citas y mensajes'}
                      </p>
                    </div>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    className={pushSuscrito ? 'border-emerald-200 text-emerald-700 hover:bg-emerald-100' : 'border-amber-200 text-amber-700 hover:bg-amber-100'}
                    onClick={pushSuscrito ? desuscribirPush : suscribirPush}
                    disabled={pushCargando}
                  >
                    {pushCargando ? <Loader2 className="h-4 w-4 animate-spin" /> : (
                      pushSuscrito ? 'Desactivar' : 'Activar'
                    )}
                  </Button>
                </div>
              )}
              {pushSoportado && pushPermiso === 'denied' && (
                <div className="flex items-center gap-3 p-3 rounded-lg bg-red-50">
                  <BellOff className="h-4 w-4 text-red-500" />
                  <div>
                    <p className="text-sm font-medium text-red-700">Bloqueadas por el navegador</p>
                    <p className="text-xs text-red-500">
                      Usa una ventana normal (no incógnito) o haz clic en el 🔒 de la barra de direcciones para activar notificaciones.
                    </p>
                  </div>
                </div>
              )}
              {!pushSoportado && (
                <div className="flex items-center gap-3 p-3 rounded-lg bg-gray-50">
                  <BellOff className="h-4 w-4 text-gray-400" />
                  <div>
                    <p className="text-sm text-slate-600">No disponibles en este navegador</p>
                    <p className="text-xs text-slate-400">
                      Usa Chrome, Edge o Safari en modo normal (no incógnito) para activar notificaciones.
                    </p>
                  </div>
                </div>
              )}
            </div>

            <div className="border-t border-slate-100 pt-4">
              <h3 className="text-sm font-medium text-slate-700 mb-3 flex items-center gap-1.5">
                <Users className="h-4 w-4" />
                Contacto de emergencia
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <CampoPerfil
                  icon={User}
                  label="Nombre"
                  value={perfil?.emergencia_nombre}
                  editando={editando}
                  editValue={form.emergencia_nombre}
                  onChange={(v: string) => setForm({ ...form, emergencia_nombre: v })}
                />
                <CampoPerfil
                  icon={Phone}
                  label="Teléfono"
                  value={perfil?.emergencia_telefono}
                  editando={editando}
                  editValue={form.emergencia_telefono}
                  onChange={(v: string) => setForm({ ...form, emergencia_telefono: v })}
                />
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
