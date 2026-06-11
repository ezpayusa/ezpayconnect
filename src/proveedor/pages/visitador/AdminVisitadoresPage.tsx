import { useState } from 'react'
import { useVisitadoresEmpresa } from '@/proveedor/hooks/useVisitadoresEmpresa'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { toast } from 'sonner'
import { UserPlus, Users, Mail, Phone, Copy, MessageCircle, CheckCircle, Clock, AlertCircle } from 'lucide-react'

export default function AdminVisitadoresPage() {
  const { visitadores, invitaciones, loading, invitarVisitador } = useVisitadoresEmpresa()
  const { cuenta, puede } = useProveedorAuth()
  const [mostrarForm, setMostrarForm] = useState(false)
  const [email, setEmail] = useState('')
  const [nombre, setNombre] = useState('')
  const [telefono, setTelefono] = useState('')
  const [invitando, setInvitando] = useState(false)
  const [linkGenerado, setLinkGenerado] = useState<string | null>(null)

  const esAdmin = puede('visitadores.gestionar')

  if (!esAdmin) {
    return (
      <div className="p-8 text-center">
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">Solo administradores pueden gestionar visitadores.</p>
      </div>
    )
  }

  const handleInvitar = async () => {
    if (!email || !nombre) {
      toast.error('Email y nombre son obligatorios')
      return
    }
    setInvitando(true)
    setLinkGenerado(null)
    const result = await invitarVisitador(email, nombre, telefono || undefined)
    setInvitando(false)
    if (result.success && result.url) {
      setLinkGenerado(result.url)
      setEmail('')
      setNombre('')
      setTelefono('')
    }
  }

  const copiarLink = () => {
    if (!linkGenerado) return
    navigator.clipboard.writeText(linkGenerado)
    toast.success('Link copiado al portapapeles')
  }

  const enviarPorWhatsApp = () => {
    if (!linkGenerado) return
    const mensaje = encodeURIComponent(
      `¡Hola! Te invitamos a unirte como Visitador Médico en EzPayConnect. Completa tu registro aquí: ${linkGenerado}`
    )
    window.open(`https://wa.me/?text=${mensaje}`, '_blank')
  }

  const enviarWhatsAppInvitacion = (url: string, nombre: string) => {
    const mensaje = encodeURIComponent(
      `¡Hola ${nombre}! Te invitamos a unirte como Visitador Médico en EzPayConnect. Completa tu registro aquí: ${url}`
    )
    window.open(`https://wa.me/?text=${mensaje}`, '_blank')
  }

  return (
    <div className="p-4 max-w-4xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Visitadores Médicos</h1>
          <p className="text-muted-foreground">Gestiona el equipo de visitadores de tu empresa.</p>
        </div>
        <Button onClick={() => { setMostrarForm(!mostrarForm); setLinkGenerado(null) }}>
          <UserPlus className="w-4 h-4 mr-2" />
          {mostrarForm ? 'Cancelar' : 'Invitar Visitador'}
        </Button>
      </div>

      {mostrarForm && (
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Invitar nuevo visitador</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium">Nombre completo</label>
                <Input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Juan Pérez" />
              </div>
              <div>
                <label className="text-sm font-medium">Email</label>
                <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="juan@empresa.com" />
              </div>
            </div>
            <div>
              <label className="text-sm font-medium">Teléfono (opcional)</label>
              <Input value={telefono} onChange={(e) => setTelefono(e.target.value)} placeholder="+502 1234 5678" />
            </div>
            <Button onClick={handleInvitar} disabled={invitando}>
              {invitando ? 'Creando invitación...' : 'Generar link de invitación'}
            </Button>

            {linkGenerado && (
              <div className="mt-4 p-4 bg-green-50 border border-green-200 rounded-lg space-y-3">
                <div className="flex items-center gap-2 text-green-700">
                  <CheckCircle className="w-5 h-5" />
                  <p className="font-medium">Invitación creada exitosamente</p>
                </div>
                <div className="bg-white p-3 rounded border text-sm break-all text-muted-foreground">
                  {linkGenerado}
                </div>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={copiarLink}>
                    <Copy className="w-4 h-4 mr-2" />
                    Copiar link
                  </Button>
                  <Button variant="outline" size="sm" className="bg-green-600 text-white hover:bg-green-700 border-green-600" onClick={enviarPorWhatsApp}>
                    <MessageCircle className="w-4 h-4 mr-2" />
                    Enviar por WhatsApp
                  </Button>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Invitaciones pendientes */}
      {invitaciones.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-lg font-semibold">Invitaciones pendientes</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {invitaciones.filter(i => i.estado === 'pendiente').map((inv) => {
              const url = `${window.location.origin}/proveedor/registro-visitador?token=${inv.token}`
              const expirada = new Date(inv.expires_at) < new Date()
              return (
                <Card key={inv.id} className={expirada ? 'opacity-60' : ''}>
                  <CardContent className="p-4 space-y-2">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="h-8 w-8 rounded-full bg-primary/10 flex items-center justify-center text-primary font-bold text-xs">
                          {inv.nombre_completo.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()}
                        </div>
                        <div>
                          <p className="font-medium text-sm">{inv.nombre_completo}</p>
                          <p className="text-xs text-muted-foreground">{inv.email}</p>
                        </div>
                      </div>
                      <Badge variant={expirada ? 'destructive' : 'outline'} className="text-xs">
                        {expirada ? 'Expirada' : 'Pendiente'}
                      </Badge>
                    </div>
                    {!expirada && (
                      <div className="flex gap-2 pt-1">
                        <Button variant="outline" size="sm" className="flex-1" onClick={() => { navigator.clipboard.writeText(url); toast.success('Link copiado') }}>
                          <Copy className="w-3 h-3 mr-1" />
                          Copiar
                        </Button>
                        <Button variant="outline" size="sm" className="flex-1 bg-green-600 text-white hover:bg-green-700 border-green-600" onClick={() => enviarWhatsAppInvitacion(url, inv.nombre_completo)}>
                          <MessageCircle className="w-3 h-3 mr-1" />
                          WhatsApp
                        </Button>
                      </div>
                    )}
                  </CardContent>
                </Card>
              )
            })}
          </div>
        </div>
      )}

      {/* Visitadores activos */}
      <div className="space-y-3">
        <h2 className="text-lg font-semibold">Visitadores activos ({visitadores.length})</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {visitadores.map((v) => (
            <Card key={v.id}>
              <CardContent className="p-4 space-y-3">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center text-primary font-bold">
                      {v.nombre_completo.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()}
                    </div>
                    <div>
                      <h3 className="font-semibold">{v.nombre_completo}</h3>
                      <Badge variant="outline" className="text-xs">Visitador Médico</Badge>
                    </div>
                  </div>
                </div>

                <Separator />

                <div className="space-y-1 text-sm text-muted-foreground">
                  <p className="flex items-center gap-2">
                    <Mail className="w-4 h-4" /> {v.email}
                  </p>
                  {v.telefono && (
                    <p className="flex items-center gap-2">
                      <Phone className="w-4 h-4" /> {v.telefono}
                    </p>
                  )}
                </div>

                <div className="grid grid-cols-2 gap-2 pt-2">
                  <div className="bg-muted rounded p-2 text-center">
                    <p className="text-lg font-bold">{v.visitas_asignadas || 0}</p>
                    <p className="text-xs text-muted-foreground">Visitas asignadas</p>
                  </div>
                  <div className="bg-green-50 rounded p-2 text-center">
                    <p className="text-lg font-bold text-green-700">{v.visitas_completadas || 0}</p>
                    <p className="text-xs text-green-600">Completadas</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>

      {visitadores.length === 0 && !loading && (
        <div className="text-center py-12 text-muted-foreground">
          <Users className="mx-auto h-12 w-12 mb-4" />
          <h3 className="text-lg font-medium">No hay visitadores registrados</h3>
          <p className="mt-1">Invita a tu primer visitador médico para comenzar.</p>
        </div>
      )}
    </div>
  )
}
