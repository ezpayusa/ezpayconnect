import { useState, useEffect } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'
import { mapearErrorRpc } from '@/lib/erroresRpc'
import { toast } from 'sonner'
import { Loader2, MapPin, AlertCircle, CheckCircle } from 'lucide-react'

export default function RegistroClinicaPage() {
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token')

  const [validando, setValidando] = useState(true)
  const [invitacion, setInvitacion] = useState<any>(null)
  const [error, setError] = useState<string | null>(null)

  const [nombreContacto, setNombreContacto] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [registrando, setRegistrando] = useState(false)
  const [registrado, setRegistrado] = useState(false)

  useEffect(() => {
    if (!token) {
      setError('No se proporcionó un token de invitación. Solicita una nueva invitación.')
      setValidando(false)
      return
    }

    const validar = async () => {
      try {
        const { data, error } = await supabase.functions.invoke('validar-invitacion-clinica', {
          body: { token },
        })

        if (error || data?.error) {
          setError(data?.error || 'Invitación no válida o expirada.')
        } else {
          const inv = data.data
          setInvitacion(inv)
          // valor inicial del campo: el contacto de la invitación, si viene
          if (typeof inv?.nombre_contacto === 'string' && inv.nombre_contacto.trim()) {
            setNombreContacto(inv.nombre_contacto.trim())
          }
        }
      } catch (err) {
        setError('Error al validar la invitación. Intenta de nuevo más tarde.')
      }
      setValidando(false)
    }

    validar()
  }, [token])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!invitacion) return

    const contacto = nombreContacto.trim()
    if (!contacto) {
      toast.error('Escribe el nombre de la persona de contacto.')
      return
    }
    if (password !== confirmPassword) {
      toast.error('Las contraseñas no coinciden')
      return
    }
    if (password.length < 6) {
      toast.error('La contraseña debe tener al menos 6 caracteres')
      return
    }

    // la edge v19 exige el correo de la invitación; sin él no se llama (sería RC004 igual)
    if (!invitacion.email) {
      toast.error(mapearErrorRpc({ code: 'RC004' }).mensaje)
      return
    }

    setRegistrando(true)

    try {
      const { data, error } = await supabase.functions.invoke('registrar-clinica-invitacion', {
        body: {
          token,
          email: invitacion.email,
          password,
          nombre_contacto: contacto,
        },
      })

      if (!error && data?.ok === true) {
        setRegistrado(true)
        toast.success('¡Registro completado exitosamente!')
      } else {
        // no-2xx: supabase-js deja la Response en error.context; el código ({ error: 'RC00x' }) se lee de ahí.
        // Se muestra solo el texto mapeado, nunca el string del servidor.
        let codigo: unknown = data?.error
        const ctx = (error as { context?: { json?: () => Promise<unknown> } } | null)?.context
        if (ctx && typeof ctx.json === 'function') {
          try {
            codigo = ((await ctx.json()) as { error?: unknown } | null)?.error
          } catch {
            codigo = null
          }
        }
        toast.error(mapearErrorRpc({ code: typeof codigo === 'string' ? codigo : null }).mensaje)
      }
    } catch {
      toast.error(mapearErrorRpc(null).mensaje)
    } finally {
      setRegistrando(false)
    }
  }

  if (validando) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <Loader2 className="w-8 h-8 animate-spin mx-auto mb-4 text-[#1E5C8E]" />
          <p className="text-gray-600">Validando invitación...</p>
        </div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <Card className="w-full max-w-md">
          <CardContent className="pt-6 text-center">
            <AlertCircle className="w-12 h-12 text-red-500 mx-auto mb-4" />
            <h2 className="text-xl font-bold text-gray-900 mb-2">Invitación Inválida</h2>
            <p className="text-gray-600 mb-4">{error}</p>
            <Link to="/login">
              <Button variant="outline">Ir al Login</Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    )
  }

  if (registrado) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <Card className="w-full max-w-md">
          <CardContent className="pt-6 text-center">
            <CheckCircle className="w-12 h-12 text-green-500 mx-auto mb-4" />
            <h2 className="text-xl font-bold text-gray-900 mb-2">¡Registro Completado!</h2>
            <p className="text-gray-600 mb-4">
              <strong>{invitacion?.nombre_clinica}</strong> ha sido registrada exitosamente.
            </p>
            <Link to="/login">
              <Button className="bg-[#1E5C8E] hover:bg-[#164a70]">Iniciar Sesión</Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4 py-8">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <div className="w-12 h-12 bg-[#1E5C8E]/10 rounded-full flex items-center justify-center mx-auto mb-3">
            <MapPin className="w-6 h-6 text-[#1E5C8E]" />
          </div>
          <CardTitle className="text-xl">Registro de Clínica</CardTitle>
          <p className="text-sm text-gray-500">
            <strong>{invitacion?.nombre_clinica}</strong>
          </p>
          <p className="text-xs text-gray-400">{invitacion?.email}</p>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <Label htmlFor="nombreContacto">Nombre de contacto</Label>
              <Input
                id="nombreContacto"
                type="text"
                value={nombreContacto}
                onChange={(e) => setNombreContacto(e.target.value)}
                placeholder="Nombre de la persona de contacto"
                maxLength={120}
                autoComplete="name"
              />
            </div>
            <div>
              <Label htmlFor="password">Contraseña</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Mínimo 6 caracteres"
                required
              />
            </div>
            <div>
              <Label htmlFor="confirmPassword">Confirmar Contraseña</Label>
              <Input
                id="confirmPassword"
                type="password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="Repite tu contraseña"
                required
              />
            </div>
            <Button
              type="submit"
              className="w-full bg-[#1E5C8E] hover:bg-[#164a70]"
              disabled={registrando}
            >
              {registrando ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Registrando...
                </>
              ) : (
                'Completar Registro'
              )}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
