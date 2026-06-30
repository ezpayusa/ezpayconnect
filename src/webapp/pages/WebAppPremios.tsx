import { useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useProgramaPuntos, type Premio } from '@/webapp/hooks/useProgramaPuntos'
import InvitarAmigoButton from '@/webapp/components/InvitarAmigoButton'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from '@/components/ui/dialog'
import { Gift, Star, Loader2, Trophy, Clock, CheckCircle2, XCircle, PackageCheck } from 'lucide-react'

function imagenUrl(path: string | null): string | null {
  if (!path) return null
  return supabase.storage.from('premios').getPublicUrl(path).data.publicUrl
}

const ESTADO_BADGE: Record<string, { label: string; className: string; icon: any }> = {
  pendiente: { label: 'Pendiente', className: 'bg-amber-50 text-amber-700 border-amber-200', icon: Clock },
  aprobado:  { label: 'Aprobado',  className: 'bg-emerald-50 text-emerald-700 border-emerald-200', icon: CheckCircle2 },
  rechazado: { label: 'Rechazado', className: 'bg-red-50 text-red-700 border-red-200', icon: XCircle },
  entregado: { label: 'Entregado', className: 'bg-sky-50 text-sky-700 border-sky-200', icon: PackageCheck },
}

export default function WebAppPremios() {
  const { saldo, premios, misCanjes, loading, canjear } = useProgramaPuntos()
  const [seleccionado, setSeleccionado] = useState<Premio | null>(null)
  const [canjeando, setCanjeando] = useState(false)

  const confirmarCanje = async () => {
    if (!seleccionado) return
    setCanjeando(true)
    await canjear(seleccionado.id)
    setCanjeando(false)
    setSeleccionado(null)
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Mis Puntos</h1>
        <p className="text-slate-500 mt-1">Canjeá tus puntos por premios</p>
      </div>

      {/* Saldo + invitar */}
      <Card className="bg-gradient-to-br from-amber-400 to-orange-500 text-white border-0">
        <CardContent className="p-6 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-full bg-white/20 flex items-center justify-center">
              <Star className="h-6 w-6" />
            </div>
            <div>
              <p className="text-amber-50 text-sm">Tu saldo</p>
              <p className="text-3xl font-bold">{loading ? '—' : saldo} <span className="text-lg font-medium">pts</span></p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-amber-50 text-xs mb-2">Ganá más puntos invitando amigos</p>
            <InvitarAmigoButton variant="secondary" label="Invitá y ganá" />
          </div>
        </CardContent>
      </Card>

      {/* Catálogo de premios */}
      <div>
        <h2 className="text-lg font-semibold text-slate-800 mb-3 flex items-center gap-2">
          <Gift className="h-5 w-5 text-orange-500" /> Premios disponibles
        </h2>
        {loading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
        ) : premios.length === 0 ? (
          <Card className="bg-white border-slate-100"><CardContent className="p-6 text-center text-slate-500 text-sm">
            No hay premios disponibles en tu país por ahora.
          </CardContent></Card>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {premios.map((p) => {
              const url = imagenUrl(p.imagen_path)
              const puede = saldo >= p.costo_puntos && p.stock > 0
              return (
                <Card key={p.id} className="bg-white border-slate-100 overflow-hidden flex flex-col">
                  <div className="h-32 bg-slate-100 flex items-center justify-center overflow-hidden">
                    {url ? (
                      <img src={url} alt={p.nombre} className="w-full h-full object-cover" />
                    ) : (
                      <Gift className="h-10 w-10 text-slate-300" />
                    )}
                  </div>
                  <CardContent className="p-4 flex flex-col flex-1">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="font-semibold text-slate-800 text-sm">{p.nombre}</h3>
                      <Badge variant="outline" className="text-[10px] capitalize shrink-0">{p.tipo}</Badge>
                    </div>
                    {p.descripcion && <p className="text-xs text-slate-500 mt-1 flex-1">{p.descripcion}</p>}
                    <div className="flex items-center justify-between mt-3">
                      <span className="text-sm font-bold text-orange-600 flex items-center gap-1">
                        <Star className="h-3.5 w-3.5" /> {p.costo_puntos} pts
                      </span>
                      <span className="text-[11px] text-slate-400">{p.stock} disp.</span>
                    </div>
                    <Button
                      size="sm"
                      className="w-full mt-3 bg-orange-500 hover:bg-orange-600"
                      disabled={!puede}
                      onClick={() => setSeleccionado(p)}
                    >
                      {p.stock <= 0 ? 'Sin stock' : saldo < p.costo_puntos ? 'Puntos insuficientes' : 'Canjear'}
                    </Button>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Mis canjes */}
      <div>
        <h2 className="text-lg font-semibold text-slate-800 mb-3 flex items-center gap-2">
          <Trophy className="h-5 w-5 text-amber-500" /> Mis canjes
        </h2>
        {misCanjes.length === 0 ? (
          <Card className="bg-white border-slate-100"><CardContent className="p-6 text-center text-slate-500 text-sm">
            Todavía no canjeaste ningún premio.
          </CardContent></Card>
        ) : (
          <div className="space-y-2">
            {misCanjes.map((c) => {
              const badge = ESTADO_BADGE[c.estado] || ESTADO_BADGE.pendiente
              const Icon = badge.icon
              return (
                <Card key={c.canje_id} className="bg-white border-slate-100">
                  <CardContent className="p-4 flex items-center justify-between gap-3">
                    <div>
                      <p className="text-sm font-medium text-slate-800">{c.premio_nombre}</p>
                      <p className="text-xs text-slate-500">
                        {c.costo_puntos} pts · {new Date(c.solicitado_at).toLocaleDateString('es-GT')}
                      </p>
                      {c.estado === 'rechazado' && c.nota_resolucion && (
                        <p className="text-xs text-red-500 mt-1">Motivo: {c.nota_resolucion}</p>
                      )}
                    </div>
                    <Badge variant="outline" className={`text-[10px] shrink-0 ${badge.className}`}>
                      <Icon className="h-3 w-3 mr-1" /> {badge.label}
                    </Badge>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Modal de confirmación */}
      <Dialog open={!!seleccionado} onOpenChange={(o) => { if (!o) setSeleccionado(null) }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirmar canje</DialogTitle>
            <DialogDescription>
              {seleccionado && (
                <>¿Canjear <strong>{seleccionado.nombre}</strong> por <strong>{seleccionado.costo_puntos} puntos</strong>? La solicitud quedará pendiente de aprobación.</>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSeleccionado(null)} disabled={canjeando}>Cancelar</Button>
            <Button className="bg-orange-500 hover:bg-orange-600" onClick={confirmarCanje} disabled={canjeando}>
              {canjeando ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null} Confirmar canje
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
