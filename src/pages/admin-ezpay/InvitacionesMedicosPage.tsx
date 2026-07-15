import { useState, useEffect, useCallback } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'
import { usePaisActivo } from '@/hooks/usePaisActivo'
import { supabase } from '@/lib/supabase'
import { APP_URL } from '@/lib/app-url'
import { toast } from 'sonner'
import {
  Stethoscope,
  Plus,
  ArrowLeft,
  RefreshCw,
  Mail,
  Clock,
  CheckCircle,
  XCircle,
  Copy,
} from 'lucide-react'

interface InvitacionMedico {
  id: string
  token: string
  email: string
  nombre_completo: string
  telefono: string | null
  especialidad: string | null
  estado: string
  expires_at: string
  created_at: string
  used_at: string | null
}

export default function InvitacionesMedicosPage() {
  const navigate = useNavigate()
  const { paisId } = useParams<{ paisId: string }>()
  const { isAdmin, loading: adminLoading } = useAdminAuth()
  const { paisActivo } = usePaisActivo()
  const [invitaciones, setInvitaciones] = useState<InvitacionMedico[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogoNuevo, setDialogoNuevo] = useState(false)
  const [nuevaInvitacion, setNuevaInvitacion] = useState({
    email: '',
    nombre_completo: '',
    telefono: '',
    especialidad_id: '',   // '' = "sin especialidad" (la define el médico)
  })
  const [especialidades, setEspecialidades] = useState<{ id: string; nombre: string }[]>([])
  const [enviando, setEnviando] = useState(false)

  const pais_id = paisId || paisActivo?.id

  // Catálogo de especialidades activas (RLS mig 181 permite SELECT a authenticated; sin RPC nueva).
  useEffect(() => {
    supabase.from('especialidades').select('id, nombre').eq('activo', true).order('nombre')
      .then(({ data }) => setEspecialidades(data || []))
  }, [])

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard')
    }
  }, [adminLoading, isAdmin, navigate])

  const cargarInvitaciones = useCallback(async () => {
    if (!pais_id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('invitaciones_medico')
      .select('*')
      .eq('pais_id', pais_id)
      .order('created_at', { ascending: false })

    if (error) {
      toast.error('Error cargando invitaciones: ' + error.message)
    } else {
      setInvitaciones(data || [])
    }
    setLoading(false)
  }, [pais_id])

  useEffect(() => {
    cargarInvitaciones()
  }, [cargarInvitaciones])

  const handleCrearInvitacion = async () => {
    if (!nuevaInvitacion.email || !nuevaInvitacion.nombre_completo || !pais_id) {
      toast.error('Email y nombre completo son requeridos')
      return
    }

    setEnviando(true)
    try {
      const espSel = especialidades.find((e) => e.id === nuevaInvitacion.especialidad_id)
      const { error } = await supabase.functions.invoke('crear-invitacion-medico', {
        body: {
          pais_id,
          email: nuevaInvitacion.email,
          nombre_completo: nuevaInvitacion.nombre_completo,
          telefono: nuevaInvitacion.telefono || null,
          especialidad: espSel?.nombre || null,       // texto legacy en paralelo (nombre del catálogo)
          especialidad_id: nuevaInvitacion.especialidad_id || null,
        },
      })

      if (error) {
        toast.error('Error: ' + error.message)
      } else {
        toast.success('Invitación enviada a ' + nuevaInvitacion.email)
        setDialogoNuevo(false)
        setNuevaInvitacion({ email: '', nombre_completo: '', telefono: '', especialidad_id: '' })
        cargarInvitaciones()
      }
    } catch (err: any) {
      toast.error('Error: ' + err.message)
    } finally {
      setEnviando(false)
    }
  }

  const copiarLink = (token: string) => {
    const url = `${APP_URL}/registro-medico?token=${token}`
    navigator.clipboard.writeText(url)
    toast.success('Link copiado al portapapeles')
  }

  const getEstadoIcon = (estado: string) => {
    switch (estado) {
      case 'pendiente': return <Clock className="w-4 h-4 text-amber-500" />
      case 'usada': return <CheckCircle className="w-4 h-4 text-green-500" />
      case 'expirada': return <XCircle className="w-4 h-4 text-red-500" />
      default: return <Clock className="w-4 h-4 text-gray-400" />
    }
  }

  if (adminLoading) return <div className="flex justify-center p-8">Verificando permisos...</div>
  if (!isAdmin) return null

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate(`/admin-ezpay/pais/${pais_id}`)}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Stethoscope className="w-6 h-6 text-[#1E5C8E]" />
              Invitaciones de Médicos
            </h1>
            <p className="text-sm text-muted-foreground">
              {paisActivo?.nombre || 'País seleccionado'}
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={cargarInvitaciones}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
          <Button onClick={() => setDialogoNuevo(true)} className="bg-[#1E5C8E] hover:bg-[#164a70]">
            <Plus className="h-4 w-4 mr-2" /> Nueva Invitación
          </Button>
        </div>
      </div>

      {/* Lista de invitaciones */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Invitaciones ({invitaciones.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center p-8">Cargando...</div>
          ) : invitaciones.length === 0 ? (
            <div className="text-center py-8 text-gray-500">
              <Mail className="w-12 h-12 mx-auto mb-3 text-gray-300" />
              <p>No hay invitaciones enviadas</p>
              <p className="text-sm">Haz clic en "Nueva Invitación" para invitar un médico</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-3 px-4">Nombre</th>
                    <th className="text-left py-3 px-4">Email</th>
                    <th className="text-left py-3 px-4">Especialidad</th>
                    <th className="text-left py-3 px-4">Estado</th>
                    <th className="text-left py-3 px-4">Expira</th>
                    <th className="text-right py-3 px-4">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {invitaciones.map((inv) => (
                    <tr key={inv.id} className="border-b hover:bg-gray-50">
                      <td className="py-3 px-4 font-medium">{inv.nombre_completo}</td>
                      <td className="py-3 px-4">{inv.email}</td>
                      <td className="py-3 px-4">{inv.especialidad || '-'}</td>
                      <td className="py-3 px-4">
                        <span className="flex items-center gap-1">
                          {getEstadoIcon(inv.estado)}
                          <span className="capitalize">{inv.estado}</span>
                        </span>
                      </td>
                      <td className="py-3 px-4 text-muted-foreground">
                        {new Date(inv.expires_at).toLocaleDateString()}
                      </td>
                      <td className="py-3 px-4 text-right">
                        {inv.estado === 'pendiente' && (
                          <Button variant="ghost" size="sm" onClick={() => copiarLink(inv.token)}>
                            <Copy className="w-4 h-4" />
                          </Button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Dialogo Nueva Invitación */}
      <Dialog open={dialogoNuevo} onOpenChange={setDialogoNuevo}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Stethoscope className="h-5 w-5 text-[#1E5C8E]" />
              Invitar Médico
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Email *</Label>
              <Input
                type="email"
                value={nuevaInvitacion.email}
                onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, email: e.target.value })}
                placeholder="doctor@ejemplo.com"
              />
            </div>
            <div>
              <Label>Nombre Completo *</Label>
              <Input
                value={nuevaInvitacion.nombre_completo}
                onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, nombre_completo: e.target.value })}
                placeholder="Dr. Juan Pérez"
              />
            </div>
            <div>
              <Label>Teléfono</Label>
              <Input
                value={nuevaInvitacion.telefono}
                onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, telefono: e.target.value })}
                placeholder="+502 1234 5678"
              />
            </div>
            <div>
              <Label>Especialidad</Label>
              <Select
                value={nuevaInvitacion.especialidad_id || '__none__'}
                onValueChange={(val) => setNuevaInvitacion({ ...nuevaInvitacion, especialidad_id: val === '__none__' ? '' : val })}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Sin especialidad (la define el médico)" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">Sin especialidad (la define el médico)</SelectItem>
                  {especialidades.map((e) => (
                    <SelectItem key={e.id} value={e.id}>{e.nombre}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoNuevo(false)}>Cancelar</Button>
              <Button
                onClick={handleCrearInvitacion}
                disabled={enviando || !nuevaInvitacion.email || !nuevaInvitacion.nombre_completo}
                className="bg-[#1E5C8E] hover:bg-[#164a70]"
              >
                {enviando ? 'Enviando...' : 'Enviar Invitación'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
