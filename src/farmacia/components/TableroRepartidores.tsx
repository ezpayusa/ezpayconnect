import { Loader2, RefreshCw, Bike } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { useTableroRepartidores } from '@/farmacia/hooks/useGestionEntregas'
import { mensajeErrorEntrega } from '@/farmacia/lib/gestionEntregas'

interface Props {
  /** Filtro voluntario de sucursal (el servidor ya confina a las sucursales que el usuario ve). */
  farmaciaId: number | null
}

// Tablero del gerente: carga de cada repartidor (tablero_repartidores, mig 353). Se refresca solo cada 30 s.
export default function TableroRepartidores({ farmaciaId }: Props) {
  const { repartidores, loading, error, actualizado, recargar } = useTableroRepartidores(farmaciaId)

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-xs text-[#8a9aaa]">
          {actualizado ? `Actualizado ${actualizado.toLocaleTimeString('es-GT', { hour: '2-digit', minute: '2-digit' })} · se refresca cada 30 s` : 'Cargando…'}
        </p>
        <Button size="sm" variant="outline" onClick={() => void recargar()} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-1 ${loading ? 'animate-spin' : ''}`} /> Actualizar
        </Button>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{mensajeErrorEntrega(error)}</div>
      )}

      {!error && loading && repartidores.length === 0 && (
        <div className="flex justify-center py-10 text-[#8a9aaa]"><Loader2 className="h-6 w-6 animate-spin" /></div>
      )}

      {!error && !loading && repartidores.length === 0 && (
        <p className="text-sm text-[#8a9aaa] text-center py-10">No hay repartidores activos en tus sucursales.</p>
      )}

      {repartidores.length > 0 && (
        <div className="overflow-x-auto rounded-lg border border-gray-100">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Repartidor</TableHead>
                <TableHead>Sucursal</TableHead>
                <TableHead>Estado</TableHead>
                <TableHead className="text-center">Asignadas</TableHead>
                <TableHead className="text-center">En camino</TableHead>
                <TableHead className="text-center">Entregadas hoy</TableHead>
                <TableHead className="text-center">Fallidas hoy</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {repartidores.map((r) => (
                <TableRow key={r.repartidor_id}>
                  <TableCell className="text-sm font-medium text-[#1a2a3a]">
                    <span className="inline-flex items-center gap-1.5"><Bike className="h-4 w-4 text-[#1E5C8E]" />{r.nombre}</span>
                  </TableCell>
                  <TableCell className="text-sm">{r.sucursal_nombre ?? 'Sin sucursal'}</TableCell>
                  <TableCell>
                    {r.estado_calc === 'libre' ? (
                      <span className="text-xs font-semibold px-2 py-0.5 rounded-full border bg-emerald-50 text-emerald-700 border-emerald-200">Libre</span>
                    ) : (
                      <span className="text-xs font-semibold px-2 py-0.5 rounded-full border bg-blue-50 text-blue-700 border-blue-200">En ruta</span>
                    )}
                  </TableCell>
                  <TableCell className="text-sm text-center">{r.asignadas}</TableCell>
                  <TableCell className="text-sm text-center">{r.en_camino}</TableCell>
                  <TableCell className="text-sm text-center">{r.entregadas_hoy}</TableCell>
                  <TableCell className="text-sm text-center">{r.fallidas_hoy}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
      {/* "Hoy" (entregadas_hoy / fallidas_hoy) se cuenta en UTC, igual que el servidor (CURRENT_DATE). */}
    </div>
  )
}
