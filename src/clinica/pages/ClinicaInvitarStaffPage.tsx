import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { UserPlus, ArrowLeft, Send } from 'lucide-react'

export default function ClinicaInvitarStaffPage() {
  const navigate = useNavigate()
  const { clinica } = useClinicaAuth()
  const [form, setForm] = useState({
    email: '',
    nombre_completo: '',
    telefono: '',
    rol: 'secretaria',
  })
  const [enviando, setEnviando] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!form.email || !form.nombre_completo) {
      toast.error('Email y nombre completo son requeridos')
      return
    }

    setEnviando(true)
    try {
      // La creación de usuario (auth.admin) y el envío de email requieren
      // service role -> se hace en la edge function 'crear-staff-clinica'.
      const { data, error } = await supabase.functions.invoke('crear-staff-clinica', {
        body: {
          email: form.email,
          nombre_completo: form.nombre_completo,
          telefono: form.telefono || null,
          rol: form.rol,
          clinica_id: clinica?.id,
          pais_id: clinica?.pais_id,
          clinica_nombre: clinica?.nombre,
        },
      })

      // La función devuelve error en el body si algo falló
      const errMsg = (error as any)?.message || (data as any)?.error
      if (errMsg) {
        toast.error('Error: ' + errMsg)
        setEnviando(false)
        return
      }

      if (data?.email_enviado) {
        toast.success(`${form.rol} registrado. Se enviaron las credenciales por email.`)
      } else {
        // Si no se pudo enviar email, mostrar la contraseña temporal para entregarla manualmente
        toast.success(
          `${form.rol} registrado. Contraseña temporal: ${data?.password ?? '(ver con admin)'}`,
          { duration: 15000 }
        )
      }
      navigate('/clinica/personal')
    } catch (err: any) {
      toast.error('Error: ' + (err.message || 'No se pudo registrar el staff'))
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="max-w-xl mx-auto">
      <div className="flex items-center gap-4 mb-6">
        <Button variant="ghost" size="icon" onClick={() => navigate('/clinica/personal')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <UserPlus className="w-6 h-6 text-[#1E5C8E]" />
            Agregar Staff
          </h1>
          <p className="text-sm text-muted-foreground">{clinica?.nombre}</p>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Datos del Staff</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <Label>Email *</Label>
              <Input
                type="email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                placeholder="staff@ejemplo.com"
                required
              />
            </div>
            <div>
              <Label>Nombre Completo *</Label>
              <Input
                value={form.nombre_completo}
                onChange={(e) => setForm({ ...form, nombre_completo: e.target.value })}
                placeholder="María López"
                required
              />
            </div>
            <div>
              <Label>Rol *</Label>
              <Select value={form.rol} onValueChange={(v) => setForm({ ...form, rol: v })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="secretaria">Secretaria</SelectItem>
                  <SelectItem value="asistente">Asistente</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Teléfono</Label>
              <Input
                value={form.telefono}
                onChange={(e) => setForm({ ...form, telefono: e.target.value })}
                placeholder="+502 1234 5678"
              />
            </div>
            <Button
              type="submit"
              className="w-full bg-[#1E5C8E] hover:bg-[#164a70]"
              disabled={enviando}
            >
              {enviando ? 'Registrando...' : (
                <>
                  <Send className="w-4 h-4 mr-2" />
                  Registrar Staff
                </>
              )}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
