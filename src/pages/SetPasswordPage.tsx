import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Loader2, Lock, CheckCircle2 } from 'lucide-react'
import { toast } from 'sonner'

export default function SetPasswordPage() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const next = params.get('next') || '/'
  const [ready, setReady] = useState(false)
  const [checking, setChecking] = useState(true)
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let active = true
    const sub = supabase.auth.onAuthStateChange((_e, session) => {
      if (!active) return
      if (session) { setReady(true); setChecking(false) }
    })
    supabase.auth.getSession().then(({ data }) => {
      if (!active) return
      if (data.session) setReady(true)
      setChecking(false)
    })
    return () => { active = false; sub.data.subscription.unsubscribe() }
  }, [])

  const guardar = async (e: React.FormEvent) => {
    e.preventDefault()
    if (password.length < 6) { toast.error('La contraseña debe tener al menos 6 caracteres'); return }
    if (password !== confirm) { toast.error('Las contraseñas no coinciden'); return }
    setSaving(true)
    const { error } = await supabase.auth.updateUser({ password, data: { must_change_password: false } })
    setSaving(false)
    if (error) { toast.error(error.message || 'No se pudo actualizar la contraseña'); return }
    toast.success('Contraseña actualizada')
    navigate(next, { replace: true })
  }

  if (checking) {
    return <div className="min-h-screen flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
  }
  if (!ready) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4">
        <Card className="w-full max-w-md"><CardContent className="p-8 text-center space-y-3">
          <Lock className="mx-auto h-10 w-10 text-slate-400" />
          <h2 className="text-lg font-semibold">Enlace no válido o vencido</h2>
          <p className="text-sm text-muted-foreground">Volvé a solicitar el restablecimiento de contraseña.</p>
          <Button onClick={() => navigate('/login')}>Ir al inicio de sesión</Button>
        </CardContent></Card>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-slate-50">
      <Card className="w-full max-w-md">
        <CardContent className="p-8 space-y-5">
          <div className="text-center space-y-1">
            <CheckCircle2 className="mx-auto h-10 w-10 text-emerald-500" />
            <h1 className="text-xl font-semibold">Establecé tu contraseña</h1>
            <p className="text-sm text-muted-foreground">Elegí una contraseña nueva para tu cuenta.</p>
          </div>
          <form onSubmit={guardar} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="pw">Contraseña nueva</Label>
              <Input id="pw" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} placeholder="••••••••" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="pw2">Confirmar contraseña</Label>
              <Input id="pw2" type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)} required minLength={6} placeholder="••••••••" />
            </div>
            <Button type="submit" className="w-full" disabled={saving}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Guardar contraseña
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
