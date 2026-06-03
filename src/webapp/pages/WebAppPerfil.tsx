import { useState } from 'react'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { supabase } from '@/lib/supabase'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  User, Mail, Phone, Calendar, AlertTriangle, MapPin, Heart, Users,
  Pencil, Save, X, Loader2
} from 'lucide-react'
import { toast } from 'sonner'

export default function WebAppPerfil() {
  const { perfil, logout } = useWebAppAuth()
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
      // Recargar página para ver cambios
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

  const InfoItem = ({ icon: Icon, label, value, editValue, onChange, type = 'text' }: any) => (
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
              <InfoItem
                icon={User}
                label="Nombre"
                value={perfil?.nombre}
                editValue={form.nombre}
                onChange={(v: string) => setForm({ ...form, nombre: v })}
              />
              <InfoItem
                icon={User}
                label="Apellido"
                value={perfil?.apellido}
                editValue={form.apellido}
                onChange={(v: string) => setForm({ ...form, apellido: v })}
              />
              <InfoItem
                icon={Mail}
                label="Email"
                value={perfil?.email}
                editValue={perfil?.email || ''}
              />
              <InfoItem
                icon={Phone}
                label="Teléfono"
                value={perfil?.telefono}
                editValue={form.telefono}
                onChange={(v: string) => setForm({ ...form, telefono: v })}
              />
              <InfoItem
                icon={Calendar}
                label="Fecha de nacimiento"
                value={perfil?.fecha_nacimiento ? new Date(perfil.fecha_nacimiento).toLocaleDateString('es-GT') : ''}
                editValue={form.fecha_nacimiento}
                onChange={(v: string) => setForm({ ...form, fecha_nacimiento: v })}
                type="date"
              />
              <InfoItem
                icon={User}
                label="Género"
                value={perfil?.genero}
                editValue={form.genero}
                onChange={(v: string) => setForm({ ...form, genero: v })}
              />
            </div>

            <InfoItem
              icon={MapPin}
              label="Dirección"
              value={perfil?.direccion}
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
              <InfoItem
                icon={AlertTriangle}
                label="Alergias"
                value={perfil?.alergias}
                editValue={form.alergias}
                onChange={(v: string) => setForm({ ...form, alergias: v })}
              />
            )}

            <InfoItem
              icon={Heart}
              label="Notas médicas"
              value={perfil?.notas}
              editValue={form.notas}
              onChange={(v: string) => setForm({ ...form, notas: v })}
            />

            <div className="border-t border-slate-100 pt-4">
              <h3 className="text-sm font-medium text-slate-700 mb-3 flex items-center gap-1.5">
                <Users className="h-4 w-4" />
                Contacto de emergencia
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <InfoItem
                  icon={User}
                  label="Nombre"
                  value={perfil?.emergencia_nombre}
                  editValue={form.emergencia_nombre}
                  onChange={(v: string) => setForm({ ...form, emergencia_nombre: v })}
                />
                <InfoItem
                  icon={Phone}
                  label="Teléfono"
                  value={perfil?.emergencia_telefono}
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
