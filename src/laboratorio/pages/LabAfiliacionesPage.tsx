import { useEffect, useState } from 'react'
import { useLaboratorio } from '@/laboratorio/hooks/useLaboratorio'
import { useLaboratorioPermisos } from '@/laboratorio/hooks/useLaboratorioPermisos'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Building2, Check, X, Loader2, Inbox, AlertTriangle } from 'lucide-react'

export default function LabAfiliacionesPage() {
  const { afiliaciones, invitaciones, fetchAfiliaciones, fetchInvitaciones, responderInvitacion } = useLaboratorio()
  const { tienePermiso, loading: permLoading } = useLaboratorioPermisos()
  const [loading, setLoading] = useState(true)
  const [accion, setAccion] = useState<string | null>(null)

  useEffect(() => {
    Promise.all([fetchAfiliaciones(), fetchInvitaciones()]).finally(() => setLoading(false))
  }, [fetchAfiliaciones, fetchInvitaciones])

  const responder = async (token: string, aceptar: boolean) => {
    setAccion(token + aceptar)
    await responderInvitacion(token, aceptar)
    setAccion(null)
  }

  if (!permLoading && !tienePermiso('afiliaciones_gestionar')) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">No tienes permiso para gestionar las afiliaciones del laboratorio.</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2 text-[#0c2a26]">
          <Building2 className="h-7 w-7 text-[#0E7C6B]" /> Afiliaciones
        </h1>
        <p className="text-sm text-muted-foreground">
          Clínicas con las que trabajas. Sus médicos pueden enviarte órdenes de examen.
        </p>
      </div>

      {/* Invitaciones pendientes */}
      <Card>
        <CardHeader><CardTitle className="text-lg flex items-center gap-2"><Inbox className="h-5 w-5 text-[#0E7C6B]" /> Invitaciones pendientes</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center py-6"><Loader2 className="h-6 w-6 animate-spin text-[#0E7C6B]" /></div>
          ) : invitaciones.length === 0 ? (
            <p className="text-sm text-muted-foreground py-2">No tienes invitaciones pendientes.</p>
          ) : (
            <div className="space-y-2">
              {invitaciones.map((inv) => (
                <div key={inv.id} className="flex items-center justify-between p-3 bg-amber-50 border border-amber-200 rounded-lg">
                  <div>
                    <p className="font-medium">{inv.clinica_nombre}</p>
                    <p className="text-xs text-muted-foreground">Te invitó a afiliarte · {new Date(inv.created_at).toLocaleDateString('es-GT')}</p>
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" className="bg-[#0E7C6B] hover:bg-[#0a5e51]" disabled={!!accion}
                      onClick={() => responder(inv.token, true)}>
                      {accion === inv.token + 'true' ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                      <span className="ml-1">Aceptar</span>
                    </Button>
                    <Button size="sm" variant="outline" className="text-red-600 border-red-200 hover:bg-red-50" disabled={!!accion}
                      onClick={() => responder(inv.token, false)}>
                      <X className="h-4 w-4" /> <span className="ml-1">Rechazar</span>
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Afiliaciones activas */}
      <Card>
        <CardHeader><CardTitle className="text-lg">Clínicas afiliadas</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center py-6"><Loader2 className="h-6 w-6 animate-spin text-[#0E7C6B]" /></div>
          ) : afiliaciones.length === 0 ? (
            <p className="text-sm text-muted-foreground py-2">Aún no tienes clínicas afiliadas. Acepta una invitación para empezar a recibir órdenes.</p>
          ) : (
            <div className="space-y-2">
              {afiliaciones.map((a) => (
                <div key={a.clinica_id} className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg">
                  <Building2 className="h-5 w-5 text-[#0E7C6B]" />
                  <div>
                    <p className="font-medium">{a.clinica_nombre}</p>
                    <p className="text-xs text-muted-foreground">Afiliado desde {new Date(a.desde).toLocaleDateString('es-GT')}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
