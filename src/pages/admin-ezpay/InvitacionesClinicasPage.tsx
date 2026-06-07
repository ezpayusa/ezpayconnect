import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'
import { usePaisActivo } from '@/hooks/usePaisActivo'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import {
  Building2,
  Plus,
  ArrowLeft,
  RefreshCw,
  Mail,
  Clock,
  CheckCircle,
  XCircle,
  Copy,
} from 'lucide-react'

interface InvitacionClinica {
  id: string
  token: string
  email: string
  nombre_clinica: string
  nombre_contacto: string | null
  estado: string
  expires_at: string
  created_at: string
  used_at: string | null
}

export default function InvitacionesClinicasPage() {
  const navigate = useNavigate()
  const { paisId } = useParams<{ paisId: string }>()
  const { isAdmin, loading: adminLoading } = useAdminAuth()
  const { paisActivo } = usePaisActivo()
  const [invitaciones, setInvitaciones] = useState<InvitacionClinica[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogoNuevo, setDialogoNuevo] = useState(false)
  const [nuevaInvitacion, setNuevaInvitacion] = useState({
    email: '',
    nombre_clinica: '',
    nombre_contacto: '',
    direccion: '',
    telefono: '',
  })
  const [enviando, setEnviando] = useState(false)

  const pais_id = paisId || paisActivo?.id

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard')
    }
  }, [adminLoading, isAdmin, navigate])

  const cargarInvitaciones = async () => {
    if (!pais_id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('invitaciones_clinica')
      .select('*')
      .eq('pais_id', pais_id)
      .order('created_at', { ascending: false })

    if (error) {
      toast.error('Error cargando invitaciones: ' + error.message)
    } else {
      setInvitaciones(data || [])
    }
    setLoading(false)
  }

  useEffect(() => {
    cargarInvitaciones()
  }, [pais_id])

  const handleCrearInvitacion = async () => {
    if (!nuevaInvitacion.email || !nuevaInvitacion.nombre_clinica || !pais_id) {
      toast.error('Email y nombre de clínica son requeridos')
      return
    }

    setEnviando(true)
    try {
      const { error } = await supabase.functions.invoke('crear-invitacion-clinica', {
        body: {
          pais_id,
          email: nuevaInvitacion.email,
          nombre_clinica: nuevaInvitacion.nombre_clinica,
          nombre_contacto: nuevaInvitacion.nombre_contacto || null,
          direccion: nuevaInvitacion.direccion || null,
          telefono: nuevaInvitacion.telefono || null,
        },
      })

      if (error) {
        toast.error('Error: ' + error.message)
      } else {
        toast.success('Invitación enviada a ' + nuevaInvitacion.email)
        setDialogoNuevo(false)
        setNuevaInvitacion({ email: '', nombre_clinica: '', nombre_contacto: '', direccion: '', telefono: '' })
        cargarInvitaciones()
      }
    } catch (err: any) {
      toast.error('Error: ' + err.message)
    } finally {
      setEnviando(false)
    }
  }

  const copiarLink = (token: string) => {
    const url = `https://ezpayconnect.vercel.app/registro-clinica?token=${token}`
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
              <Building2 className="w-6 h-6 text-[#1E5C8E]" />
              Invitaciones de Clínicas
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
              <p className="text-sm">Haz clic en "Nueva Invitación" para invitar una clínica</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-3 px-4">Clínica</th>
                    <th className="text-left py-3 px-4">Contacto</th>
                    <th className="text-left py-3 px-4">Email</th>
                    <th className="text-left py-3 px-4">Estado</th>
                    <th className="text-left py-3 px-4">Expira</th>
                    <th className="text-right py-3 px-4">Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {invitaciones.map((inv) => (
                    <tr key={inv.id} className="border-b hover:bg-gray-50">
                      <td className="py-3 px-4 font-medium">{inv.nombre_clinica}</td>
                      <td className="py-3 px-4">{inv.nombre_contacto || '-'}</td>
                      <td className="py-3 px-4">{inv.email}</td>
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

      <Dialog open={dialogoNuevo} onOpenChange={setDialogoNuevo}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Building2 className="h-5 w-5 text-[#1E5C8E]" />
              Invitar Clínica
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Email *</Label>
              <Input type="email" value={nuevaInvitacion.email} onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, email: e.target.value })} placeholder="clinica@ejemplo.com" />
            </div>
            <div>
              <Label>Nombre de la Clínica *</Label>
              <Input value={nuevaInvitacion.nombre_clinica} onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, nombre_clinica: e.target.value })} placeholder="Clínica San José" />
            </div>
            <div>
              <Label>Nombre del Contacto</Label>
              <Input value={nuevaInvitacion.nombre_contacto} onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, nombre_contacto: e.target.value })} placeholder="Dr. Juan Pérez" />
            </div>
            <div>
              <Label>Dirección</Label>
              <Input value={nuevaInvitacion.direccion} onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, direccion: e.target.value })} placeholder="Calle Principal 123" />
            </div>
            <div>
              <Label>Teléfono</Label>
              <Input value={nuevaInvitacion.telefono} onChange={(e) => setNuevaInvitacion({ ...nuevaInvitacion, telefono: e.target.value })} placeholder="+502 1234 5678" />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoNuevo(false)}>Cancelar</Button>
              <Button onClick={handleCrearInvitacion} disabled={enviando || !nuevaInvitacion.email || !nuevaInvitacion.nombre_clinica} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                {enviando ? 'Enviando...' : 'Enviar Invitación'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
