import { useState, useEffect } from 'react'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Loader2, Settings, Save, MapPin } from 'lucide-react'

export default function ClinicaConfiguracionPage() {
  const { clinica, loading, error, recargar } = useClinicaAuth()
  const [form, setForm] = useState({ nombre: '', direccion: '', telefono: '', email: '' })
  const [guardando, setGuardando] = useState(false)

  useEffect(() => {
    if (clinica) {
      setForm({
        nombre: clinica.nombre || '',
        direccion: clinica.direccion || '',
        telefono: clinica.telefono || '',
        email: clinica.email || '',
      })
    }
  }, [clinica])

  const handleGuardar = async () => {
    if (!clinica) return
    if (!form.nombre.trim()) {
      toast.error('El nombre de la clínica es obligatorio')
      return
    }
    setGuardando(true)
    const { error: err } = await supabase.rpc('actualizar_clinica', {
      p_clinica_id: clinica.id,
      p_nombre: form.nombre.trim(),
      p_direccion: form.direccion.trim() || null,
      p_telefono: form.telefono.trim() || null,
      p_email: form.email.trim() || null,
    })
    setGuardando(false)
    if (err) {
      toast.error('Error al guardar: ' + err.message)
      return
    }
    toast.success('Datos de la clínica actualizados')
    recargar()
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  if (!clinica) {
    return (
      <div className="max-w-2xl mx-auto">
        <Card>
          <CardContent className="p-8 text-center text-gray-600">
            <MapPin className="h-10 w-10 mx-auto mb-3 text-gray-300" />
            <p className="font-medium">{error || 'No se encontró una clínica asociada a este usuario.'}</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1a2a3a] flex items-center gap-2">
          <Settings className="h-7 w-7 text-[#1E5C8E]" />
          Configuración de la Clínica
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Edita los datos de tu clínica.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Datos generales</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label>Nombre *</Label>
            <Input
              value={form.nombre}
              onChange={(e) => setForm({ ...form, nombre: e.target.value })}
              placeholder="Nombre de la clínica"
            />
          </div>
          <div>
            <Label>Dirección</Label>
            <Input
              value={form.direccion}
              onChange={(e) => setForm({ ...form, direccion: e.target.value })}
              placeholder="Dirección"
            />
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <Label>Teléfono</Label>
              <Input
                value={form.telefono}
                onChange={(e) => setForm({ ...form, telefono: e.target.value })}
                placeholder="+502 1234 5678"
              />
            </div>
            <div>
              <Label>Email</Label>
              <Input
                type="email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                placeholder="contacto@clinica.com"
              />
            </div>
          </div>
          <div className="pt-2">
            <Button
              className="bg-[#1E5C8E] hover:bg-[#164a70]"
              onClick={handleGuardar}
              disabled={guardando || !form.nombre.trim()}
            >
              {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
              Guardar cambios
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Información</CardTitle>
        </CardHeader>
        <CardContent className="space-y-1 text-sm text-muted-foreground">
          <p><strong className="text-[#1a2a3a]">Estado:</strong> {clinica.activa ? 'Activa' : 'Inactiva'}</p>
        </CardContent>
      </Card>
    </div>
  )
}
