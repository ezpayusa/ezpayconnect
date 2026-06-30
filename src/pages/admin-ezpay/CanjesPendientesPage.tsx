import { useState, useCallback, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Gift, Loader2, CheckCircle2, XCircle, ShieldAlert } from 'lucide-react'

interface CanjePendiente {
  canje_id: number
  solicitado_at: string
  costo_puntos: number
  paciente_id: number
  paciente_nombre: string
  premio_id: number
  premio_nombre: string
  premio_tipo: string
}

export default function CanjesPendientesPage() {
  const [canjes, setCanjes] = useState<CanjePendiente[]>([])
  const [loading, setLoading] = useState(true)
  const [noAutorizado, setNoAutorizado] = useState(false)
  const [resolviendo, setResolviendo] = useState<number | null>(null)
  const [rechazando, setRechazando] = useState<CanjePendiente | null>(null)
  const [nota, setNota] = useState('')

  const cargar = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase.rpc('listar_canjes_pendientes')
    setLoading(false)
    if (error) {
      if (/no_autorizado/.test(error.message || '')) { setNoAutorizado(true); return }
      toast.error('Error cargando canjes: ' + error.message)
      return
    }
    setCanjes((Array.isArray(data) ? data : []) as CanjePendiente[])
  }, [])

  useEffect(() => { cargar() }, [cargar])

  const resolver = async (canje: CanjePendiente, aprobar: boolean, notaTexto?: string) => {
    setResolviendo(canje.canje_id)
    const { error } = await supabase.rpc('resolver_canje', {
      _canje_id: canje.canje_id,
      _aprobar: aprobar,
      _nota: notaTexto || null,
    })
    setResolviendo(null)
    if (error) {
      const m = error.message || ''
      if (/canje_ya_resuelto/.test(m)) {
        toast.info('Ese canje ya fue resuelto por otro administrador.')
      } else if (/no_autorizado/.test(m)) {
        setNoAutorizado(true)
      } else {
        toast.error('Error: ' + m)
      }
      await cargar() // refrescar lista en cualquier caso
      return
    }
    toast.success(aprobar ? 'Canje aprobado' : 'Canje rechazado (puntos y stock devueltos)')
    setRechazando(null)
    setNota('')
    await cargar()
  }

  if (noAutorizado) {
    return (
      <div className="p-8">
        <div className="flex items-center gap-3 text-red-600 bg-red-50 border border-red-200 rounded-lg p-4 max-w-md">
          <ShieldAlert className="h-5 w-5 shrink-0" />
          <p className="text-sm">No autorizado: esta sección es solo para super administradores.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800 flex items-center gap-2">
          <Gift className="h-6 w-6 text-orange-500" /> Canjes pendientes
        </h1>
        <p className="text-slate-500 mt-1">Solicitudes de canje de premios pendientes de aprobación</p>
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
      ) : canjes.length === 0 ? (
        <Card><CardContent className="p-8 text-center text-slate-500 text-sm">No hay canjes pendientes.</CardContent></Card>
      ) : (
        <div className="space-y-3">
          {canjes.map((c) => (
            <Card key={c.canje_id} className="bg-white">
              <CardContent className="p-4 flex flex-col md:flex-row md:items-center md:justify-between gap-3">
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-slate-800">{c.premio_nombre}</span>
                    <Badge variant="outline" className="text-[10px] capitalize">{c.premio_tipo}</Badge>
                    <Badge variant="outline" className="text-[10px] text-orange-600 border-orange-200">{c.costo_puntos} pts</Badge>
                  </div>
                  <p className="text-sm text-slate-500 mt-1">
                    Paciente: <span className="font-medium text-slate-700">{c.paciente_nombre}</span> (#{c.paciente_id})
                    · {new Date(c.solicitado_at).toLocaleString('es-GT')}
                  </p>
                </div>
                <div className="flex gap-2 shrink-0">
                  <Button
                    size="sm" variant="outline"
                    className="border-red-200 text-red-600 hover:bg-red-50"
                    disabled={resolviendo === c.canje_id}
                    onClick={() => { setRechazando(c); setNota('') }}
                  >
                    <XCircle className="h-4 w-4 mr-1" /> Rechazar
                  </Button>
                  <Button
                    size="sm" className="bg-emerald-600 hover:bg-emerald-700"
                    disabled={resolviendo === c.canje_id}
                    onClick={() => resolver(c, true)}
                  >
                    {resolviendo === c.canje_id ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
                    Aprobar
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Modal de rechazo con nota */}
      <Dialog open={!!rechazando} onOpenChange={(o) => { if (!o) { setRechazando(null); setNota('') } }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rechazar canje</DialogTitle>
            <DialogDescription>
              {rechazando && <>Rechazar el canje de <strong>{rechazando.premio_nombre}</strong> de {rechazando.paciente_nombre}. Se devolverán los puntos y el stock. Podés indicar un motivo.</>}
            </DialogDescription>
          </DialogHeader>
          <Textarea placeholder="Motivo del rechazo (opcional)" value={nota} onChange={(e) => setNota(e.target.value)} />
          <DialogFooter>
            <Button variant="outline" onClick={() => { setRechazando(null); setNota('') }} disabled={resolviendo !== null}>Cancelar</Button>
            <Button
              className="bg-red-600 hover:bg-red-700"
              disabled={resolviendo !== null}
              onClick={() => rechazando && resolver(rechazando, false, nota.trim() || undefined)}
            >
              {resolviendo !== null ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null} Confirmar rechazo
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
