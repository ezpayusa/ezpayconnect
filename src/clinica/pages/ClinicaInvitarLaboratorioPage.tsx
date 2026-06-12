import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { FlaskConical, ArrowLeft, Send, Building2, Clock, Loader2 } from 'lucide-react'

interface Invitacion { id: string; email: string; nombre_laboratorio: string | null; estado: string; created_at: string }
interface Afiliado { laboratorio_id: string; nombre_empresa: string; ciudad: string | null; desde: string }

export default function ClinicaInvitarLaboratorioPage() {
  const navigate = useNavigate()
  const { clinica } = useClinicaAuth()
  const [form, setForm] = useState({ email: '', nombre: '' })
  const [enviando, setEnviando] = useState(false)
  const [invitaciones, setInvitaciones] = useState<Invitacion[]>([])
  const [afiliados, setAfiliados] = useState<Afiliado[]>([])
  const [loading, setLoading] = useState(true)

  const cargar = useCallback(async () => {
    setLoading(true)
    const [inv, afi] = await Promise.all([
      supabase.from('invitaciones_laboratorio')
        .select('id, email, nombre_laboratorio, estado, created_at')
        .order('created_at', { ascending: false }),
      supabase.rpc('afiliaciones_de_clinica'),
    ])
    setInvitaciones((inv.data || []) as Invitacion[])
    setAfiliados((afi.data || []) as Afiliado[])
    setLoading(false)
  }, [])

  useEffect(() => { cargar() }, [cargar])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.email) { toast.error('El email del laboratorio es requerido'); return }
    setEnviando(true)
    const { error } = await supabase.rpc('invitar_laboratorio', {
      p_email: form.email.trim(),
      p_nombre: form.nombre.trim() || null,
    })
    setEnviando(false)
    if (error) { toast.error('Error: ' + error.message); return }
    toast.success('Invitación enviada a ' + form.email)
    setForm({ email: '', nombre: '' })
    cargar()
  }

  const estadoBadge = (e: string) =>
    e === 'aceptada' ? 'bg-green-100 text-green-700' :
    e === 'rechazada' ? 'bg-red-100 text-red-700' :
    e === 'pendiente' ? 'bg-amber-100 text-amber-700' : 'bg-slate-100 text-slate-700'

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate('/clinica/personal')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <FlaskConical className="w-6 h-6 text-[#1E5C8E]" /> Invitar Laboratorio
          </h1>
          <p className="text-sm text-muted-foreground">{clinica?.nombre} · afilia laboratorios clínicos para que tus médicos les envíen órdenes.</p>
        </div>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-lg">Datos del laboratorio</CardTitle></CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <Label>Email del laboratorio *</Label>
              <Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })}
                placeholder="contacto@laboratorio.com" required />
              <p className="text-xs text-muted-foreground mt-1">
                Si el laboratorio aún no tiene cuenta, podrá registrarse y aceptar la afiliación desde su portal.
              </p>
            </div>
            <div>
              <Label>Nombre del laboratorio (opcional)</Label>
              <Input value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })}
                placeholder="LabClinico Regional" />
            </div>
            <Button type="submit" className="w-full bg-[#1E5C8E] hover:bg-[#164a70]" disabled={enviando}>
              {enviando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Send className="w-4 h-4 mr-2" />}
              Enviar invitación
            </Button>
          </form>
        </CardContent>
      </Card>

      {/* Laboratorios afiliados */}
      <Card>
        <CardHeader><CardTitle className="text-lg flex items-center gap-2"><Building2 className="h-5 w-5 text-[#1E5C8E]" /> Laboratorios afiliados</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center py-4"><Loader2 className="h-5 w-5 animate-spin text-[#1E5C8E]" /></div>
          ) : afiliados.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aún no hay laboratorios afiliados.</p>
          ) : (
            <div className="space-y-2">
              {afiliados.map((a) => (
                <div key={a.laboratorio_id} className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                  <FlaskConical className="h-5 w-5 text-[#0E7C6B]" />
                  <div>
                    <p className="font-medium">{a.nombre_empresa}</p>
                    {a.ciudad && <p className="text-xs text-muted-foreground">{a.ciudad}</p>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Invitaciones enviadas */}
      <Card>
        <CardHeader><CardTitle className="text-lg flex items-center gap-2"><Clock className="h-5 w-5 text-[#1E5C8E]" /> Invitaciones enviadas</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center py-4"><Loader2 className="h-5 w-5 animate-spin text-[#1E5C8E]" /></div>
          ) : invitaciones.length === 0 ? (
            <p className="text-sm text-muted-foreground">No has enviado invitaciones.</p>
          ) : (
            <div className="space-y-2">
              {invitaciones.map((i) => (
                <div key={i.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div>
                    <p className="font-medium">{i.nombre_laboratorio || i.email}</p>
                    <p className="text-xs text-muted-foreground">{i.email}</p>
                  </div>
                  <Badge className={estadoBadge(i.estado)}>{i.estado}</Badge>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
