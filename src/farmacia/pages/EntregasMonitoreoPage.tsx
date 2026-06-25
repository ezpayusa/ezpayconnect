import { useEffect, useMemo, useState } from 'react'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Truck, Camera, PenLine, MapPinned, AlertTriangle, Loader2, Banknote } from 'lucide-react'
import { useEntregasMonitoreo, type EntregaMonitoreo } from '@/farmacia/hooks/useEntregasMonitoreo'
import { useFarmaciaPermisos } from '@/farmacia/hooks/useFarmaciaPermisos'
import { colorEstado, LABEL_ESTADO } from '@/repartidor/lib/estados'
import type { EstadoEntrega } from '@/repartidor/types'
import StatsSucursales from '@/farmacia/components/StatsSucursales'
import ReconciliacionPanel from '@/farmacia/components/ReconciliacionPanel'
import GeocodeEntregaDialog from '@/farmacia/components/GeocodeEntregaDialog'

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
        {/* Fallback legacy: si no hay array pero sí evidencia_path */}
        {e.evidencias.length === 0 && e.evidencia_path && (
          <button type="button" title="Ver evidencia" onClick={() => m.verEvidencia(e.evidencia_path!)} className="text-[#1E5C8E] p-1"><Camera className="h-4 w-4" /></button>
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
          <TabsTrigger value="stats">Estadísticas</TabsTrigger>
          <TabsTrigger value="reconciliacion">
            Reconciliación{m.faltantes.length > 0 ? ` (${m.faltantes.length})` : ''}
          </TabsTrigger>
        </TabsList>

        {/* LISTA */}
        <TabsContent value="lista" className="mt-3">
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
                          <button type="button" title="Corregir dirección" onClick={() => setGeoEntrega(e)} className="text-[#1E5C8E] p-1">
                            <MapPinned className="h-4 w-4" />
                          </button>
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

        {/* STATS */}
        <TabsContent value="stats" className="mt-3">
          <StatsSucursales stats={m.stats} />
        </TabsContent>

        {/* RECONCILIACIÓN */}
        <TabsContent value="reconciliacion" className="mt-3">
          <ReconciliacionPanel faltantes={m.faltantes} />
        </TabsContent>
      </Tabs>

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
