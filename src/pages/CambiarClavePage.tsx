import { useEffect, useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Loader2, KeyRound } from 'lucide-react'
import { toast } from 'sonner'

// Cambio de clave estando logueado. Antes de cambiarla se re-verifica la clave actual con
// signInWithPassword: una sesión abierta sola (un equipo prestado, una pestaña olvidada) no alcanza para
// cambiar la clave. El email sale SIEMPRE de la sesión, nunca de un input: si no, la verificación
// podría hacerse contra otra cuenta.

const MSG_CORTA = 'La clave nueva tiene que tener al menos 8 caracteres.'
const MSG_NO_COINCIDEN = 'Las claves nuevas no coinciden.'
const MSG_IGUAL = 'La clave nueva tiene que ser distinta de la actual.'
const MSG_ACTUAL_MAL = 'La clave actual no es correcta.'
const MSG_DEBIL = 'La clave nueva es muy débil: usa una más larga o con más variedad.'
const MSG_GENERICO = 'No se pudo cambiar la clave. Inténtalo de nuevo.'

function mensajeErrorUpdate(error: { code?: string; message?: string }): string {
  if (error.code === 'same_password' || /different from the old/i.test(error.message ?? '')) return MSG_IGUAL
  if (error.code === 'weak_password') return MSG_DEBIL
  return MSG_GENERICO
}

export default function CambiarClavePage() {
  const navigate = useNavigate()
  const [email, setEmail] = useState<string | null>(null)
  const [checking, setChecking] = useState(true)
  const [actual, setActual] = useState('')
  const [nueva, setNueva] = useState('')
  const [repetir, setRepetir] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let active = true
    supabase.auth.getUser().then(({ data }) => {
      if (!active) return
      setEmail(data.user?.email ?? null)
      setChecking(false)
    })
    return () => { active = false }
  }, [])

  const guardar = async (e: React.FormEvent) => {
    e.preventDefault()
    if (saving || !email) return
    setError(null)
    if (nueva.length < 8) { setError(MSG_CORTA); return }
    if (nueva !== repetir) { setError(MSG_NO_COINCIDEN); return }
    if (nueva === actual) { setError(MSG_IGUAL); return }

    setSaving(true)
    try {
      const { error: errActual } = await supabase.auth.signInWithPassword({ email, password: actual })
      if (errActual) { setError(MSG_ACTUAL_MAL); return }

      const { error: errUpdate } = await supabase.auth.updateUser({ password: nueva })
      if (errUpdate) { setError(mensajeErrorUpdate(errUpdate)); return }

      setActual(''); setNueva(''); setRepetir('')
      toast.success('Clave actualizada')
      navigate('/', { replace: true })
    } catch {
      setError(MSG_GENERICO)
    } finally {
      setSaving(false)
    }
  }

  if (checking) {
    return <div className="min-h-screen flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
  }
  if (!email) return <Navigate to="/login" replace />

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-slate-50">
      <Card className="w-full max-w-md">
        <CardContent className="p-8 space-y-5">
          <div className="text-center space-y-1">
            <KeyRound className="mx-auto h-10 w-10 text-emerald-500" />
            <h1 className="text-xl font-semibold">Cambiar clave</h1>
            <p className="text-sm text-muted-foreground">Confirma tu clave actual y elige una nueva.</p>
          </div>
          <form onSubmit={guardar} className="space-y-4" noValidate>
            <div className="space-y-2">
              <Label htmlFor="clave_actual">Clave actual</Label>
              <Input id="clave_actual" type="password" autoComplete="current-password" value={actual} onChange={(e) => setActual(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="clave_nueva">Clave nueva</Label>
              <Input id="clave_nueva" type="password" autoComplete="new-password" value={nueva} onChange={(e) => setNueva(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="clave_repetir">Repetir clave nueva</Label>
              <Input id="clave_repetir" type="password" autoComplete="new-password" value={repetir} onChange={(e) => setRepetir(e.target.value)} />
            </div>
            {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
            <Button type="submit" className="w-full" disabled={saving}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Guardar clave
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
