import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useWebAppAuth } from '@/webapp/hooks/useWebAppAuth'
import { usePaisesRegistro } from '@/hooks/usePaisesRegistro'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Mail, Lock, User, Loader2, Globe } from 'lucide-react'
import { toast } from 'sonner'

export default function WebAppRegistroPage() {
  const navigate = useNavigate()
  const { register } = useWebAppAuth()
  const { paises, error: paisesError } = usePaisesRegistro()
  const [form, setForm] = useState({
    nombre: '', apellido: '', email: '', password: '', telefono: '', pais_id: ''
  })
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.nombre || !form.apellido || !form.email || !form.password) {
      toast.error('Completa todos los campos obligatorios')
      return
    }
    setLoading(true)
    const { error } = await register(form.email, form.password, {
      nombre: form.nombre,
      apellido: form.apellido,
      telefono: form.telefono || null,
      pais_id: form.pais_id || undefined
    })
    if (error) {
      toast.error('Error al registrarse: ' + (error as Error).message)
    } else {
      toast.success('Registro exitoso. Revisa tu email para confirmar.')
      navigate('/paciente/login')
    }
    setLoading(false)
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-sky-50 to-indigo-50 flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-xl p-8 space-y-6">
        <div className="text-center space-y-2">
          <div className="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-br from-sky-500 to-indigo-500 flex items-center justify-center">
            <span className="text-white font-bold text-2xl">E</span>
          </div>
          <h1 className="text-2xl font-bold text-slate-800">Crear Cuenta</h1>
          <p className="text-slate-500">Únete a EzPayConnect</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Nombre</Label>
              <Input value={form.nombre} onChange={e => setForm({...form, nombre: e.target.value})} required />
            </div>
            <div className="space-y-2">
              <Label>Apellido</Label>
              <Input value={form.apellido} onChange={e => setForm({...form, apellido: e.target.value})} required />
            </div>
          </div>
          <div className="space-y-2">
            <Label>Email</Label>
            <Input type="email" value={form.email} onChange={e => setForm({...form, email: e.target.value})} required />
          </div>
          <div className="space-y-2">
            <Label>Teléfono</Label>
            <Input value={form.telefono} onChange={e => setForm({...form, telefono: e.target.value})} />
          </div>
          <div className="space-y-2">
            <Label className="flex items-center gap-1">
              <Globe className="h-3.5 w-3.5" /> País
            </Label>
            <select
              value={form.pais_id}
              onChange={e => setForm({...form, pais_id: e.target.value})}
              className="w-full h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
              required={paises.length > 0}
            >
              <option value="">Selecciona tu país</option>
              {paises.map((p) => (
                <option key={p.id} value={p.id}>{p.nombre}</option>
              ))}
            </select>
            {paisesError && (
              <p className="text-xs text-red-500">Error cargando países: {paisesError}</p>
            )}
            {paises.length === 0 && !paisesError && (
              <p className="text-xs text-amber-600">No hay países disponibles. Contacta soporte.</p>
            )}
          </div>
          <div className="space-y-2">
            <Label>Contraseña</Label>
            <Input type="password" value={form.password} onChange={e => setForm({...form, password: e.target.value})} required />
          </div>
          <Button type="submit" className="w-full bg-gradient-to-r from-sky-500 to-indigo-500 hover:from-sky-600 hover:to-indigo-600" disabled={loading}>
            {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
            Registrarme
          </Button>
        </form>

        <p className="text-center text-sm text-slate-500">
          ¿Ya tienes cuenta?{' '}
          <button onClick={() => navigate('/paciente/login')} className="text-sky-600 font-medium hover:underline">
            Inicia sesión
          </button>
        </p>
      </div>
    </div>
  )
}
