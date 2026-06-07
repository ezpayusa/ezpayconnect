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
      // Para staff (secretaria/asistente), creamos directamente el usuario
      // ya que no necesitan una invitación con token como los médicos
      const password = Math.random().toString(36).slice(-8) + 'A1!'

      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email: form.email,
        password,
        email_confirm: true,
      })

      if (authError) {
        if (authError.message?.includes('already')) {
          toast.error('Este email ya está registrado')
          setEnviando(false)
          return
        }
        throw authError
      }

      const userId = authData.user!.id

      // Crear perfil
      await supabase.from('perfiles').insert({
        id: userId,
        email: form.email,
        nombre_completo: form.nombre_completo,
        rol: form.rol,
        pais_id: clinica?.pais_id,
        activo: true,
      })

      // Asociar a la clínica
      await supabase.from('medico_clinicas').insert({
        medico_id: userId,
        clinica_id: clinica?.id,
        es_principal: false,
      })

      // Enviar email con credenciales
      const resendApiKey = Deno.env.get('RESEND_API_KEY')
      if (resendApiKey) {
        await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${resendApiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: 'EzPayConnect <onboarding@resend.dev>',
            to: form.email,
            subject: 'Bienvenido a EzPayConnect — Credenciales de acceso',
            html: `<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;border:1px solid #e5e7eb;border-radius:8px;">
              <h2 style="color:#1E5C8E;margin-top:0;">¡Bienvenido a EzPayConnect!</h2>
              <p>Hola <strong>${form.nombre_completo}</strong>,</p>
              <p>Has sido registrado como <strong>${form.rol}</strong> en <strong>${clinica?.nombre}</strong>.</p>
              <p>Tus credenciales de acceso:</p>
              <div style="background:#f3f4f6;padding:12px;border-radius:6px;margin:12px 0;">
                <p><strong>Email:</strong> ${form.email}</p>
                <p><strong>Contraseña temporal:</strong> ${password}</p>
              </div>
              <p><a href="https://ezpayconnect.vercel.app/login" style="color:#1E5C8E;">Iniciar sesión</a></p>
              <p style="color:#6b7280;font-size:12px;">Te recomendamos cambiar tu contraseña al iniciar sesión.</p>
            </div>`,
          }),
        })
      }

      toast.success(`${form.rol} registrado exitosamente`)
      navigate('/clinica/personal')
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
