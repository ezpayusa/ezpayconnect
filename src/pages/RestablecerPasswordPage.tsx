import { useState, useEffect } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Loader2, KeyRound, CheckCircle } from 'lucide-react'

// Pantalla a la que llega el usuario desde el enlace del correo de recuperación.
// Supabase establece una sesión de tipo "recovery" al detectar el token en la URL;
// con esa sesión, updateUser({ password }) fija la nueva contraseña.
export default function RestablecerPasswordPage() {
  const navigate = useNavigate()
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [loading, setLoading] = useState(false)
  const [listo, setListo] = useState(false)
  const [haySesion, setHaySesion] = useState(false)

  useEffect(() => {
    // La sesión de recovery puede llegar al montar (detectSessionInUrl) o por evento.
    supabase.auth.getSession().then(({ data }) => { if (data.session) setHaySesion(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY' || session) setHaySesion(true)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (password.length < 6) {
      toast.error('La contraseña debe tener al menos 6 caracteres')
      return
    }
    if (password !== confirm) {
      toast.error('Las contraseñas no coinciden')
      return
    }
    setLoading(true)
    const { error } = await supabase.auth.updateUser({ password })
    setLoading(false)
    if (error) {
      toast.error(
        error.message.toLowerCase().includes('session')
          ? 'Enlace inválido o expirado. Solicita uno nuevo desde "Recuperar contraseña".'
          : error.message
      )
      return
    }
    setListo(true)
    await supabase.auth.signOut()
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-blue-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-xl">
        <CardHeader className="text-center">
          <div className="mx-auto w-12 h-12 rounded-xl bg-[#1E5C8E] flex items-center justify-center mb-3">
            <KeyRound className="h-6 w-6 text-white" />
          </div>
          <CardTitle className="text-xl">Nueva contraseña</CardTitle>
          <p className="text-sm text-muted-foreground">Elige una contraseña nueva para tu cuenta.</p>
        </CardHeader>
        <CardContent>
          {listo ? (
            <div className="text-center space-y-4">
              <CheckCircle className="mx-auto h-12 w-12 text-green-600" />
              <p className="text-sm text-muted-foreground">
                Tu contraseña fue actualizada. Ya puedes iniciar sesión.
              </p>
              <Button className="w-full bg-[#1E5C8E] hover:bg-[#164a70]" onClick={() => navigate('/login')}>
                Iniciar sesión
              </Button>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              {!haySesion && (
                <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded p-2">
                  Abre esta página desde el enlace que te llegó por correo. Si no llegaste desde ahí, el
                  cambio podría fallar.
                </p>
              )}
              <div className="space-y-2">
                <Label htmlFor="password">Nueva contraseña</Label>
                <Input id="password" type="password" placeholder="••••••••" value={password}
                  onChange={(e) => setPassword(e.target.value)} required minLength={6} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="confirm">Confirmar contraseña</Label>
                <Input id="confirm" type="password" placeholder="••••••••" value={confirm}
                  onChange={(e) => setConfirm(e.target.value)} required minLength={6} />
              </div>
              <Button type="submit" className="w-full bg-[#1E5C8E] hover:bg-[#164a70]" disabled={loading}>
                {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                Guardar contraseña
              </Button>
              <div className="text-center text-xs text-muted-foreground">
                <Link to="/login" className="hover:underline">Volver al inicio de sesión</Link>
              </div>
            </form>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
