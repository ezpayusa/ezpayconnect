import { useEffect, useMemo, useState } from 'react'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Truck, Camera, PenLine, MapPinned, AlertTriangle, Loader2, Banknote, UserPlus, Repeat } from 'lucide-react'
import { Checkbox } from '@/components/ui/checkbox'
import { toast } from 'sonner'
import { useEntregasMonitoreo, type EntregaMonitoreo } from '@/farmacia/hooks/useEntregasMonitoreo'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { colorEstado, LABEL_ESTADO } from '@/repartidor/lib/estados'
import type { EstadoEntrega } from '@/repartidor/types'
import StatsSucursales from '@/farmacia/components/StatsSucursales'
import ReconciliacionPanel from '@/farmacia/components/ReconciliacionPanel'
import GeocodeEntregaDialog from '@/farmacia/components/GeocodeEntregaDialog'
import TableroRepartidores from '@/farmacia/components/TableroRepartidores'
import AsignarRepartidorDialog from '@/farmacia/components/AsignarRepartidorDialog'
import { MAX_LOTE, puedeAsignar, puedeReasignar, sucursalUnica } from '@/farmacia/lib/gestionEntregas'

const ESTADOS: EstadoEntrega[] = ['pendiente', 'asignada', 'en_camino', 'entregada', 'fallida']

export default function EntregasMonitoreoPage() {
  const m = useEntregasMonitoreo()
  const { tienePermiso } = useFarmaciaPermisos()
  const puedeGestionar = tienePermiso('entregas_gestionar')

  // Filtros (selector de sucursal/delivery = FILTRO VOLUNTARIO; opciones derivadas de las filas, NO confinamiento).
  const [estado, setEstado] = useState<string>('todas')
  const [sucursal, setSucursal] = useState<string>('todas')
  const [delivery, setDelivery] = useState<string>('todos')
  const [desde, setDesde] = useState<string>('')
  const [hasta, setHasta] = useState<string>('')
  const [geoEntrega, setGeoEntrega] = useState<EntregaMonitoreo | null>(null)
  // Asignación (mig 353): selección de pendientes para la tanda y el diálogo abierto (tanda o reasignación).
  const [seleccion, setSeleccion] = useState<Set<number>>(new Set())
  const [dialogo, setDialogo] = useState<{ modo: 'asignar' | 'reasignar'; ids: number[]; actual?: string | null } | null>(null)

  const filtros = useMemo(() => ({
    estado: estado === 'todas' ? null : (estado as EstadoEntrega),
    sucursalId: sucursal === 'todas' ? null : Number(sucursal),
    deliveryId: delivery === 'todos' ? null : delivery,
    desde: desde || null,
    hasta: hasta || null,
  }), [estado, sucursal, delivery, desde, hasta])

  const recargar = () => {
    void m.cargarLista(filtros)
    void m.cargarStats(filtros.desde, filtros.hasta, filtros.sucursalId)
    void m.cargarReconciliacion(filtros.sucursalId)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { recargar() }, [filtros])

  // La selección solo guarda pendientes que siguen en la lista (tras recargar, lo asignado sale solo).
  useEffect(() => {
    setSeleccion((prev) => {
      const vivas = new Set(m.entregas.filter(puedeAsignar).map((e) => e.id))
      const next = new Set([...prev].filter((id) => vivas.has(id)))
      return next.size === prev.size ? prev : next
    })
  }, [m.entregas])

  const seleccionadas = useMemo(() => m.entregas.filter((e) => seleccion.has(e.id)), [m.entregas, seleccion])
  const sucursalSel = sucursalUnica(seleccionadas)
  const toggleSel = (id: number) => setSeleccion((prev) => {
    const next = new Set(prev)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    return next
  })
  const abrirTanda = () => {
    if (seleccionadas.length === 0) return
    if (sucursalSel == null) { toast.error('Elegí entregas de una sola sucursal: cada repartidor es de una sucursal.'); return }
    if (seleccionadas.length > MAX_LOTE) { toast.error(`Podés asignar hasta ${MAX_LOTE} entregas por tanda.`); return }
    setDialogo({ modo: 'asignar', ids: seleccionadas.map((e) => e.id) })
  }
  const alTerminarAsignacion = () => {
    const d = dialogo
    setDialogo(null)
    setSeleccion(new Set())
    if (d) toast.success(d.modo === 'asignar'
      ? (d.ids.length === 1 ? 'Entrega asignada. El repartidor recibió el aviso.' : `${d.ids.length} entregas asignadas. El repartidor recibió el aviso.`)
      : 'Entrega reasignada. Avisamos a los dos repartidores.')
    recargar()
  }

  // Opciones de los selectores: DERIVADAS de las filas devueltas (el RPC ya confinó) — Q1: no leemos sucursal del exento.
  const sucursalesOpts = useMemo(() => {
    const map = new Map<number, string>()
    m.entregas.forEach((e) => { if (!map.has(e.farmacia_id)) map.set(e.farmacia_id, e.sucursal_nombre ?? `Sucursal ${e.farmacia_id}`) })
    return [...map.entries()]
  }, [m.entregas])
  const deliveriesOpts = useMemo(() => {
    const map = new Map<string, string>()
    m.entregas.forEach((e) => { if (e.delivery_id && !map.has(e.delivery_id)) map.set(e.delivery_id, e.delivery_nombre ?? 'Repartidor') })
    return [...map.entries()]
  }, [m.entregas])

  const verEvidencias = (e: EntregaMonitoreo) => {
    const foto = e.evidencias.filter((x) => x.tipo === 'foto').at(-1)
    const firma = e.evidencias.filter((x) => x.tipo === 'firma').at(-1)
    return (
      <div className="flex gap-1">
        {foto && (
          <button type="button" title="Ver foto" onClick={() => m.verEvidencia(foto.path)} className="text-[#1E5C8E] p-1"><Camera className="h-4 w-4" /></button>
        )}
        {firma && (
          <button type="button" title="Ver firma" onClick={() => m.verEvidencia(firma.path)} className="text-[#1E5C8E] p-1"><PenLine className="h-4 w-4" /></button>
        )}
      </div>
    )
  }

  return (
    <div className="p-4 max-w-[1400px] mx-auto space-y-4">
      <div className="flex items-center gap-2">
        <Truck className="h-6 w-6 text-[#1E5C8E]" />
        <h1 className="text-xl font-bold text-[#1a2a3a]">Monitoreo de entregas</h1>
      </div>

      {/* Filtros */}
      <div className="flex flex-wrap gap-2 items-end">
        <div className="space-y-1">
          <label className="text-xs text-[#8a9aaa]">Estado</label>
          <Select value={estado} onValueChange={setEstado}>
            <SelectTrigger className="w-36 h-9"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="todas">Todos</SelectItem>
              {ESTADOS.map((s) => <SelectItem key={s} value={s}>{LABEL_ESTADO[s]}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <label className="text-xs text-[#8a9aaa]">Sucursal</label>
          <Select value={sucursal} onValueChange={setSucursal}>
            <SelectTrigger className="w-44 h-9"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="todas">Todas</SelectItem>
              {sucursalesOpts.map(([id, nombre]) => <SelectItem key={id} value={String(id)}>{nombre}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <label className="text-xs text-[#8a9aaa]">Repartidor</label>
          <Select value={delivery} onValueChange={setDelivery}>
            <SelectTrigger className="w-44 h-9"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos</SelectItem>
              {deliveriesOpts.map(([id, nombre]) => <SelectItem key={id} value={id}>{nombre}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <label className="text-xs text-[#8a9aaa]">Desde</label>
          <Input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="w-40 h-9" />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-[#8a9aaa]">Hasta</label>
          <Input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="w-40 h-9" />
        </div>
      </div>

      <Tabs defaultValue="lista">
        <TabsList>
          <TabsTrigger value="lista">Lista</TabsTrigger>
          <TabsTrigger value="repartidores">Repartidores</TabsTrigger>
          <TabsTrigger value="stats">Estadísticas</TabsTrigger>
          <TabsTrigger value="reconciliacion">
            Reconciliación{m.faltantes.length > 0 ? ` (${m.faltantes.length})` : ''}
          </TabsTrigger>
        </TabsList>

        {/* LISTA */}
        <TabsContent value="lista" className="mt-3">
          {/* Barra de la tanda: solo con entregas_gestionar y con pendientes seleccionadas */}
          {puedeGestionar && seleccionadas.length > 0 && (
            <div className="mb-3 rounded-lg border border-[#1E5C8E]/20 bg-[#1E5C8E]/5 px-3 py-2 flex flex-wrap items-center gap-3 text-sm">
              <span className="font-medium text-[#1a2a3a]">
                {seleccionadas.length === 1 ? '1 pendiente seleccionada' : `${seleccionadas.length} pendientes seleccionadas`}
              </span>
              {sucursalSel == null && <span className="text-amber-700">Son de sucursales distintas: elegí de una sola.</span>}
              <div className="ml-auto flex gap-2">
                <Button size="sm" variant="outline" onClick={() => setSeleccion(new Set())}>Limpiar</Button>
                <Button size="sm" className="bg-[#1E5C8E] hover:bg-[#164a70]" disabled={sucursalSel == null} onClick={abrirTanda}>
                  <UserPlus className="h-4 w-4 mr-1" /> Asignar a…
                </Button>
              </div>
            </div>
          )}
          {m.loading && (
            <div className="flex justify-center py-10 text-[#8a9aaa]"><Loader2 className="h-6 w-6 animate-spin" /></div>
          )}
          {!m.loading && m.error && (
            <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 flex items-center justify-between">
              <span>No se pudo cargar el monitoreo.</span>
              <Button size="sm" variant="outline" onClick={recargar}>Reintentar</Button>
            </div>
          )}
          {!m.loading && !m.error && m.entregas.length === 0 && (
            <p className="text-sm text-[#8a9aaa] text-center py-10">No hay entregas para estos filtros.</p>
          )}
          {!m.loading && !m.error && m.entregas.length > 0 && (
            <div className="overflow-x-auto rounded-lg border border-gray-100">
              <Table>
                <TableHeader>
                  <TableRow>
                    {puedeGestionar && <TableHead className="w-8"></TableHead>}
                    <TableHead>Estado</TableHead>
                    <TableHead>Paciente</TableHead>
                    <TableHead>Sucursal</TableHead>
                    <TableHead>Repartidor</TableHead>
                    <TableHead>Monto</TableHead>
                    <TableHead>Int.</TableHead>
                    <TableHead>Flags</TableHead>
                    <TableHead>Evidencia</TableHead>
                    <TableHead></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {m.entregas.map((e) => (
                    <TableRow key={e.id}>
                      {puedeGestionar && (
                        <TableCell>
                          {puedeAsignar(e) && (
                            <Checkbox checked={seleccion.has(e.id)} onCheckedChange={() => toggleSel(e.id)} aria-label="Seleccionar para asignar" />
                          )}
                        </TableCell>
                      )}
                      <TableCell>
                        <span className={`text-xs font-semibold px-2 py-0.5 rounded-full border ${colorEstado(e.estado)}`}>{LABEL_ESTADO[e.estado]}</span>
                      </TableCell>
                      <TableCell className="text-sm">
                        <p className="font-medium text-[#1a2a3a]">{e.paciente_nombre ?? '—'}</p>
                        <p className="text-xs text-[#8a9aaa] truncate max-w-[200px]">{e.direccion_entrega ?? 'Sin dirección'}</p>
                      </TableCell>
                      <TableCell className="text-sm">{e.sucursal_nombre ?? `Sucursal ${e.farmacia_id}`}</TableCell>
                      <TableCell className="text-sm">{e.delivery_nombre ?? '—'}</TableCell>
                      <TableCell className="text-sm">
                        {e.monto != null ? `Q${Number(e.monto).toFixed(2)}` : '—'}
                        {e.cobrado && <span className="ml-1 text-emerald-600" title="Cobrado"><Banknote className="h-3.5 w-3.5 inline" /></span>}
                      </TableCell>
                      <TableCell className="text-sm text-center">{e.intentos}</TableCell>
                      <TableCell>
                        <div className="flex gap-1">
                          {e.disc_monto && (
                            <span title="#1 Monto cobrado menor al despachado" className="text-[10px] font-semibold text-amber-700 bg-amber-100 border border-amber-200 rounded px-1.5 py-0.5">$≠</span>
                          )}
                          {e.disc_cobrada_fallida && (
                            <span title="#3 Marcada fallida pero con cobro registrado" className="text-[10px] font-semibold text-red-700 bg-red-100 border border-red-200 rounded px-1.5 py-0.5">⚑</span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>{verEvidencias(e)}</TableCell>
                      <TableCell>
                        {puedeGestionar && (
                          <div className="flex gap-1">
                            {puedeAsignar(e) && (
                              <button type="button" title="Asignar repartidor" onClick={() => setDialogo({ modo: 'asignar', ids: [e.id] })} className="text-[#1E5C8E] p-1">
                                <UserPlus className="h-4 w-4" />
                              </button>
                            )}
                            {puedeReasignar(e) && (
                              <button type="button" title="Reasignar" onClick={() => setDialogo({ modo: 'reasignar', ids: [e.id], actual: e.delivery_id })} className="text-[#1E5C8E] p-1">
                                <Repeat className="h-4 w-4" />
                              </button>
                            )}
                            <button type="button" title="Corregir dirección" onClick={() => setGeoEntrega(e)} className="text-[#1E5C8E] p-1">
                              <MapPinned className="h-4 w-4" />
                            </button>
                          </div>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
          {/* Leyenda de flags */}
          {!m.loading && m.entregas.some((e) => e.disc_monto || e.disc_cobrada_fallida) && (
            <p className="text-xs text-[#8a9aaa] mt-2 flex items-center gap-3">
              <AlertTriangle className="h-3.5 w-3.5 text-amber-600" />
              <span><b>$≠</b> = monto cobrado &lt; despachado (#1)</span>
              <span><b>⚑</b> = fallida con cobro (#3)</span>
            </p>
          )}
        </TabsContent>

        {/* REPARTIDORES: carga de cada uno (tablero_repartidores, refresco cada 30 s) */}
        <TabsContent value="repartidores" className="mt-3">
          <TableroRepartidores farmaciaId={filtros.sucursalId} />
        </TabsContent>

        {/* STATS */}
        <TabsContent value="stats" className="mt-3">
          <StatsSucursales stats={m.stats} error={m.statsError} onReintentar={recargar} />
        </TabsContent>

        {/* RECONCILIACIÓN */}
        <TabsContent value="reconciliacion" className="mt-3">
          <ReconciliacionPanel faltantes={m.faltantes} error={m.reconError} onReintentar={recargar} />
        </TabsContent>
      </Tabs>

      {dialogo && (
        <AsignarRepartidorDialog
          modo={dialogo.modo}
          entregaIds={dialogo.ids}
          repartidorActual={dialogo.actual}
          onHecho={alTerminarAsignacion}
          onClose={() => setDialogo(null)}
        />
      )}

      {geoEntrega && (
        <GeocodeEntregaDialog
          entrega={geoEntrega}
          geocodificar={m.geocodificar}
          guardarDireccion={m.guardarDireccion}
          onSaved={recargar}
          onClose={() => setGeoEntrega(null)}
        />
      )}
    </div>
  )
}
