import { useState, useEffect } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { supabase } from '@/lib/supabase'
import { FlaskConical, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

export default function LabRegistro() {
  const navigate = useNavigate()
  const { register } = useProveedorAuth()
  const [loading, setLoading] = useState(false)
  const [step, setStep] = useState<1 | 2>(1)
  const [paises, setPaises] = useState<{ id: string; nombre: string }[]>([])

  const [form, setForm] = useState({
    nombre_empresa: '', ruc_nit: '', pais_id: '', ciudad: '', direccion: '',
    email_contacto: '', telefono: '', nombre_completo: '', email: '', password: '', confirmPassword: '',
  })
  const update = (f: string, v: string) => setForm((p) => ({ ...p, [f]: v }))

  useEffect(() => {
    supabase.from('configuracion_pais').select('id, nombre').eq('activo', true).order('nombre')
      .then(({ data }) => setPaises((data || []) as { id: string; nombre: string }[]))
  }, [])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (step === 1) {
      if (!form.nombre_empresa || !form.email_contacto || !form.pais_id) {
        toast.error('Completa los campos obligatorios (incluido el país)')
        return
      }
      setStep(2)
      return
    }
    if (form.password !== form.confirmPassword) { toast.error('Las contraseñas no coinciden'); return }
    if (form.password.length < 6) { toast.error('La contraseña debe tener al menos 6 caracteres'); return }

    setLoading(true)
    const { error } = await register(form.email, form.password, form.nombre_completo, {
      nombre_empresa: form.nombre_empresa,
      tipo: 'laboratorio_clinico',
      ruc_nit: form.ruc_nit || null,
      pais_id: form.pais_id || null,
      ciudad: form.ciudad || null,
      direccion: form.direccion || null,
      email_contacto: form.email_contacto,
      telefono: form.telefono || null,
    })
    setLoading(false)
    if (error) { toast.error('Error al registrar', { description: error.message }); return }
    toast.success('Laboratorio registrado. Ya puedes iniciar sesión.')
    navigate('/laboratorio/login')
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-emerald-50 to-teal-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-lg shadow-xl">
        <CardHeader className="text-center">
          <div className="mx-auto w-12 h-12 rounded-xl bg-[#0E7C6B] flex items-center justify-center mb-4">
            <FlaskConical className="h-6 w-6 text-white" />
          </div>
          <CardTitle className="text-xl">Registro de Laboratorio Clínico</CardTitle>
          <p className="text-sm text-muted-foreground">{step === 1 ? 'Datos del laboratorio' : 'Datos del representante'}</p>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            {step === 1 ? (
              <>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2 md:col-span-2">
                    <Label>Nombre del laboratorio *</Label>
                    <Input value={form.nombre_empresa} onChange={(e) => update('nombre_empresa', e.target.value)} placeholder="Ej: LabClinico Regional" required />
                  </div>
                  <div className="space-y-2">
                    <Label>País *</Label>
                    <select value={form.pais_id} onChange={(e) => update('pais_id', e.target.value)}
                      className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm" required>
                      <option value="">Selecciona tu país</option>
                      {paises.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label>RUC / NIT</Label>
                    <Input value={form.ruc_nit} onChange={(e) => update('ruc_nit', e.target.value)} />
                  </div>
                  <div className="space-y-2">
                    <Label>Email de contacto *</Label>
                    <Input type="email" value={form.email_contacto} onChange={(e) => update('email_contacto', e.target.value)} placeholder="contacto@laboratorio.com" required />
                  </div>
                  <div className="space-y-2">
                    <Label>Teléfono</Label>
                    <Input value={form.telefono} onChange={(e) => update('telefono', e.target.value)} />
                  </div>
                  <div className="space-y-2">
                    <Label>Ciudad</Label>
                    <Input value={form.ciudad} onChange={(e) => update('ciudad', e.target.value)} />
                  </div>
                  <div className="space-y-2 md:col-span-2">
                    <Label>Dirección</Label>
                    <Input value={form.direccion} onChange={(e) => update('direccion', e.target.value)} />
                  </div>
                </div>
                <Button type="submit" className="w-full bg-[#0E7C6B] hover:bg-[#0a5e51]">Continuar</Button>
              </>
            ) : (
              <>
                <div className="space-y-2">
                  <Label>Nombre completo del representante *</Label>
                  <Input value={form.nombre_completo} onChange={(e) => update('nombre_completo', e.target.value)} required />
                </div>
                <div className="space-y-2">
                  <Label>Correo electrónico (usuario) *</Label>
                  <Input type="email" value={form.email} onChange={(e) => update('email', e.target.value)} required />
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Contraseña *</Label>
                    <Input type="password" value={form.password} onChange={(e) => update('password', e.target.value)} placeholder="Mínimo 6 caracteres" required />
                  </div>
                  <div className="space-y-2">
                    <Label>Confirmar contraseña *</Label>
                    <Input type="password" value={form.confirmPassword} onChange={(e) => update('confirmPassword', e.target.value)} required />
                  </div>
                </div>
                <div className="flex gap-3 pt-2">
                  <Button type="button" variant="outline" className="flex-1" onClick={() => setStep(1)}>Atrás</Button>
                  <Button type="submit" className="flex-1 bg-[#0E7C6B] hover:bg-[#0a5e51]" disabled={loading}>
                    {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null} Registrar laboratorio
                  </Button>
                </div>
              </>
            )}
          </form>
          <div className="mt-6 text-center text-sm">
            <span className="text-muted-foreground">¿Ya tienes cuenta? </span>
            <Link to="/laboratorio/login" className="text-[#0E7C6B] hover:underline font-medium">Inicia sesión</Link>
          </div>
          <div className="mt-4 text-center text-xs text-muted-foreground">
            <Link to="/login" className="hover:underline">← Volver al portal médico</Link>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
