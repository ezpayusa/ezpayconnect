import { useState, useEffect } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { supabase } from '@/lib/supabase'
import { MapPin, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

const tiposEmpresa = [
  { value: 'farmacia', label: 'Farmacia' },
  { value: 'laboratorio_farmaceutico', label: 'Laboratorio Farmacéutico' },
  { value: 'laboratorio_clinico', label: 'Laboratorio Clínico' },
  { value: 'empresa_afin', label: 'Empresa Afín' },
]

export default function ProveedorRegistro() {
  const navigate = useNavigate()
  const { register } = useProveedorAuth()
  const [loading, setLoading] = useState(false)
  const [step, setStep] = useState<1 | 2>(1)

  const [form, setForm] = useState({
    nombre_empresa: '',
    tipo: 'farmacia',
    ruc_nit: '',
    pais_id: '',
    ciudad: '',
    direccion: '',
    email_contacto: '',
    telefono: '',
    nombre_completo: '',
    email: '',
    password: '',
    confirmPassword: '',
  })

  const [paises, setPaises] = useState<{ id: string; nombre: string }[]>([])

  useEffect(() => {
    supabase
      .from('configuracion_pais')
      .select('id, nombre')
      .eq('activo', true)
      .order('nombre')
      .then(({ data }) => setPaises((data || []) as { id: string; nombre: string }[]))
  }, [])

  const update = (field: string, value: string) => setForm((prev) => ({ ...prev, [field]: value }))

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

    if (form.password !== form.confirmPassword) {
      toast.error('Las contraseñas no coinciden')
      return
    }
    if (form.password.length < 6) {
      toast.error('La contraseña debe tener al menos 6 caracteres')
      return
    }

    setLoading(true)
    const { error } = await register(form.email, form.password, form.nombre_completo, {
      nombre_empresa: form.nombre_empresa,
      tipo: form.tipo,
      ruc_nit: form.ruc_nit || null,
      pais_id: form.pais_id || null,
      ciudad: form.ciudad || null,
      direccion: form.direccion || null,
      email_contacto: form.email_contacto,
      telefono: form.telefono || null,
    })
    setLoading(false)

    if (error) {
      toast.error('Error al registrar', { description: error.message })
    } else {
      toast.success('Empresa registrada. Tu cuenta está en revisión.')
      navigate('/proveedor/login')
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-lg shadow-xl">
        <CardHeader className="text-center">
          <div className="mx-auto w-12 h-12 rounded-xl bg-[#1E5C8E] flex items-center justify-center mb-4">
            <MapPin className="h-6 w-6 text-white" />
          </div>
          <CardTitle className="text-xl">Registro de Empresa</CardTitle>
          <p className="text-sm text-muted-foreground">
            {step === 1 ? 'Datos de la empresa' : 'Datos del representante'}
          </p>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            {step === 1 ? (
              <>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2 md:col-span-2">
                    <Label htmlFor="nombre_empresa">Nombre de la empresa *</Label>
                    <Input
                      id="nombre_empresa"
                      value={form.nombre_empresa}
                      onChange={(e) => update('nombre_empresa', e.target.value)}
                      placeholder="Ej: Farmacia Moderna"
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="tipo">Tipo de empresa *</Label>
                    <select
                      id="tipo"
                      value={form.tipo}
                      onChange={(e) => update('tipo', e.target.value)}
                      className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                      required
                    >
                      {tiposEmpresa.map((t) => (
                        <option key={t.value} value={t.value}>{t.label}</option>
                      ))}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="pais">País *</Label>
                    <select
                      id="pais"
                      value={form.pais_id}
                      onChange={(e) => update('pais_id', e.target.value)}
                      className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
                      required
                    >
                      <option value="">Selecciona tu país</option>
                      {paises.map((p) => (
                        <option key={p.id} value={p.id}>{p.nombre}</option>
                      ))}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="ruc_nit">RUC / NIT</Label>
                    <Input
                      id="ruc_nit"
                      value={form.ruc_nit}
                      onChange={(e) => update('ruc_nit', e.target.value)}
                      placeholder="123456789"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="email_contacto">Email de contacto *</Label>
                    <Input
                      id="email_contacto"
                      type="email"
                      value={form.email_contacto}
                      onChange={(e) => update('email_contacto', e.target.value)}
                      placeholder="contacto@empresa.com"
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="telefono">Teléfono</Label>
                    <Input
                      id="telefono"
                      value={form.telefono}
                      onChange={(e) => update('telefono', e.target.value)}
                      placeholder="5555-1111"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="ciudad">Ciudad</Label>
                    <Input
                      id="ciudad"
                      value={form.ciudad}
                      onChange={(e) => update('ciudad', e.target.value)}
                      placeholder="Ciudad de Guatemala"
                    />
                  </div>
                  <div className="space-y-2 md:col-span-2">
                    <Label htmlFor="direccion">Dirección</Label>
                    <Input
                      id="direccion"
                      value={form.direccion}
                      onChange={(e) => update('direccion', e.target.value)}
                      placeholder="Zona 1, 6a Avenida..."
                    />
                  </div>
                </div>
                <Button type="submit" className="w-full bg-[#1E5C8E] hover:bg-[#164a70]">
                  Continuar
                </Button>
              </>
            ) : (
              <>
                <div className="space-y-2">
                  <Label htmlFor="nombre_completo">Nombre completo del representante *</Label>
                  <Input
                    id="nombre_completo"
                    value={form.nombre_completo}
                    onChange={(e) => update('nombre_completo', e.target.value)}
                    placeholder="Juan Pérez"
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="email">Correo electrónico (usuario) *</Label>
                  <Input
                    id="email"
                    type="email"
                    value={form.email}
                    onChange={(e) => update('email', e.target.value)}
                    placeholder="juan@empresa.com"
                    required
                  />
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="password">Contraseña *</Label>
                    <Input
                      id="password"
                      type="password"
                      value={form.password}
                      onChange={(e) => update('password', e.target.value)}
                      placeholder="Mínimo 6 caracteres"
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="confirmPassword">Confirmar contraseña *</Label>
                    <Input
                      id="confirmPassword"
                      type="password"
                      value={form.confirmPassword}
                      onChange={(e) => update('confirmPassword', e.target.value)}
                      placeholder="Repite la contraseña"
                      required
                    />
                  </div>
                </div>
                <div className="flex gap-3 pt-2">
                  <Button type="button" variant="outline" className="flex-1" onClick={() => setStep(1)}>
                    Atrás
                  </Button>
                  <Button type="submit" className="flex-1 bg-[#1E5C8E] hover:bg-[#164a70]" disabled={loading}>
                    {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                    Registrar empresa
                  </Button>
                </div>
              </>
            )}
          </form>

          <div className="mt-6 text-center text-sm">
            <span className="text-muted-foreground">¿Ya tienes cuenta? </span>
            <Link to="/proveedor/login" className="text-[#1E5C8E] hover:underline font-medium">
              Inicia sesión
            </Link>
          </div>
          <div className="mt-4 text-center text-xs text-muted-foreground">
            <Link to="/login" className="hover:underline">← Volver al portal médico</Link>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
