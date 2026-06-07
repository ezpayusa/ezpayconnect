import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Stethoscope, ArrowLeft, Send } from 'lucide-react'

export default function ClinicaInvitarMedicoPage() {
  const navigate = useNavigate()
  const { clinica } = useClinicaAuth()
  const [form, setForm] = useState({
    email: '',
    nombre_completo: '',
    telefono: '',
    especialidad: '',
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
      const { error } = await supabase.functions.invoke('crear-invitacion-medico', {
        body: {
          pais_id: clinica?.pais_id,
          clinica_id: clinica?.id,
          email: form.email,
          nombre_completo: form.nombre_completo,
          telefono: form.telefono || null,
          especialidad: form.especialidad || null,
        },
      })

      if (error) {
        toast.error('Error: ' + error.message)
      } else {
        toast.success('Invitación enviada a ' + form.email)
        navigate('/clinica/personal')
      }
    } catch (err: any) {
      toast.error('Error: ' + err.message)
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
            <Stethoscope className="w-6 h-6 text-[#1E5C8E]" />
            Invitar Médico
          </h1>
          <p className="text-sm text-muted-foreground">{clinica?.nombre}</p>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Datos del Médico</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <Label>Email *</Label>
              <Input
                type="email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                placeholder="doctor@ejemplo.com"
                required
              />
            </div>
            <div>
              <Label>Nombre Completo *</Label>
              <Input
                value={form.nombre_completo}
                onChange={(e) => setForm({ ...form, nombre_completo: e.target.value })}
                placeholder="Dr. Juan Pérez"
                required
              />
            </div>
            <div>
              <Label>Teléfono</Label>
              <Input
                value={form.telefono}
                onChange={(e) => setForm({ ...form, telefono: e.target.value })}
                placeholder="+502 1234 5678"
              />
            </div>
            <div>
              <Label>Especialidad</Label>
              <Input
                value={form.especialidad}
                onChange={(e) => setForm({ ...form, especialidad: e.target.value })}
                placeholder="Cardiología"
              />
            </div>
            <Button
              type="submit"
              className="w-full bg-[#1E5C8E] hover:bg-[#164a70]"
              disabled={enviando}
            >
              {enviando ? 'Enviando...' : (
                <>
                  <Send className="w-4 h-4 mr-2" />
                  Enviar Invitación
                </>
              )}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
