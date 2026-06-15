import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Loader2, Mail, ArrowLeft, CheckCircle } from 'lucide-react'

// Pantalla compartida de "olvidé mi contraseña". Llama a resetPasswordForEmail,
// que envía el enlace de recuperación (apuntando a /restablecer-password).
// NOTA: el envío real del correo depende del SMTP de Supabase Auth (lo configura
// el equipo). La UI queda funcional para cuando el SMTP esté conectado.
export default function RecuperarPasswordPage() {
  const [email, setEmail] = useState('')
  const [loading, setLoading] = useState(false)
  const [enviado, setEnviado] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email.trim()) {
      toast.error('Ingresa tu correo electrónico')
      return
    }
    setLoading(true)
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/restablecer-password`,
    })
    setLoading(false)
    if (error) {
      toast.error(error.message)
      return
    }
    // No revelamos si el email existe (privacidad): siempre el mismo mensaje.
    setEnviado(true)
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-blue-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-md shadow-xl">
        <CardHeader className="text-center">
          <div className="mx-auto w-12 h-12 rounded-xl bg-[#1E5C8E] flex items-center justify-center mb-3">
            <Mail className="h-6 w-6 text-white" />
          </div>
          <CardTitle className="text-xl">Recuperar contraseña</CardTitle>
          <p className="text-sm text-muted-foreground">
            Te enviaremos un enlace para crear una nueva contraseña.
          </p>
        </CardHeader>
        <CardContent>
          {enviado ? (
            <div className="text-center space-y-4">
              <CheckCircle className="mx-auto h-12 w-12 text-green-600" />
              <p className="text-sm text-muted-foreground">
                Si <strong>{email}</strong> tiene una cuenta, te enviamos un correo con el enlace para
                restablecer tu contraseña. Revisa tu bandeja (y spam).
              </p>
              <Link to="/login">
                <Button variant="outline" className="w-full">Volver al inicio de sesión</Button>
              </Link>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="email">Correo electrónico</Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="tu@email.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>
              <Button type="submit" className="w-full bg-[#1E5C8E] hover:bg-[#164a70]" disabled={loading}>
                {loading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                Enviar enlace de recuperación
              </Button>
              <div className="text-center text-xs text-muted-foreground">
                <Link to="/login" className="hover:underline inline-flex items-center gap-1">
                  <ArrowLeft className="h-3 w-3" /> Volver al inicio de sesión
                </Link>
              </div>
            </form>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
