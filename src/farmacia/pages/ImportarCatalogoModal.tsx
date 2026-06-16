import { useState } from 'react'
import * as XLSX from 'xlsx'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Download, Upload, FileSpreadsheet, CheckCircle, AlertTriangle, Loader2 } from 'lucide-react'

interface Sucursal { id: number; nombre: string }
interface Props { open: boolean; onClose: () => void; sucursales: Sucursal[]; onImported?: () => void }

// Límites (defensa cliente; el RPC es la autoridad)
const MAX_BYTES = 2 * 1024 * 1024 // 2 MB
const MAX_FILAS = 5000
const CHUNK = 500 // filas por llamada al RPC (evita statement timeout en lotes grandes)

// Encabezados aceptados → campo que espera el RPC
const norm = (s: string) => s.toString().trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ')
const COLUMNAS: Record<string, string[]> = {
  nombre_medicamento: ['nombre_medicamento', 'nombre del medicamento', 'nombre', 'medicamento', 'producto'],
  presentacion: ['presentacion', 'presentación'],
  descripcion: ['descripcion', 'descripción'],
  laboratorio: ['laboratorio', 'lab'],
  stock_actual: ['stock_actual', 'stock', 'existencia', 'existencias'],
  stock_minimo: ['stock_minimo', 'stock mínimo', 'stock minimo', 'minimo'],
  precio_unitario: ['precio_unitario', 'precio unitario', 'precio'],
  fecha_vencimiento: ['fecha_vencimiento', 'fecha de vencimiento', 'vencimiento', 'caducidad'],
  activo: ['activo', 'estado'],
}
const TEMPLATE = ['nombre_medicamento', 'presentacion', 'descripcion', 'laboratorio', 'stock_actual', 'stock_minimo', 'precio_unitario', 'fecha_vencimiento', 'activo']
const EJEMPLO = ['Paracetamol 500mg', 'Tabletas', 'Analgésico', 'Bayer', 100, 10, 12.5, '2026-12-31', 'si']

// Reglas de validación ALINEADAS con el RPC cargar_catalogo_farmacia:
//  - nombre no vacío (req)
//  - stock_actual / precio_unitario / stock_minimo / fecha: blanco = OK (conserva);
//    si trae valor, debe ser numérico / fecha válida (el RPC rechaza igual si no).
//  - activo: opcional; valor no reconocido => el RPC lo ignora (conserva) => no se rechaza.
const esNumero = (v: string) => v === '' || !isNaN(Number(v.replace(',', '.')))
const esEntero = (v: string) => v === '' || /^-?\d+$/.test(v)
const esFecha = (v: string) => v === '' || !isNaN(Date.parse(v))
// Clave normalizada EQUIVALENTE a private.norm_med_nombre (acentos fuera → colapsa
// espacios → quita espacio dígito↔unidad "500 mg"->"500mg" → trim → upper). Solo para
// ADVERTIR dups intra-archivo en el preview; el de-dup autoritativo es el RPC (anti-drift).
const claveNorm = (s: string) =>
  s.normalize('NFD').replace(/[̀-ͯ]/g, '')   // acentos/ñ fuera (NFD + quita diacríticos)
    .replace(/\s+/g, ' ')                       // colapsa espacios
    .replace(/(\d)\s+([A-Za-z])/g, '$1$2')      // "500 mg" -> "500mg" (todos los pares)
    .trim().toUpperCase()

interface Fila { raw: Record<string, string>; errores: string[]; warn?: string }

export default function ImportarCatalogoModal({ open, onClose, sucursales, onImported }: Props) {
  const [farmaciaId, setFarmaciaId] = useState<string>(sucursales.length === 1 ? String(sucursales[0].id) : '')
  const [filas, setFilas] = useState<Fila[]>([])
  const [nombreArchivo, setNombreArchivo] = useState('')
  const [parsing, setParsing] = useState(false)
  const [cargando, setCargando] = useState(false)
  const [reporte, setReporte] = useState<{ insertadas: number; actualizadas: number; rechazadas: { fila: number; motivo: string }[]; error?: string } | null>(null)

  const validas = filas.filter((f) => f.errores.length === 0)
  const invalidas = filas.filter((f) => f.errores.length > 0)

  const descargarPlantilla = () => {
    const ws = XLSX.utils.aoa_to_sheet([TEMPLATE, EJEMPLO])
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, ws, 'Catalogo')
    XLSX.writeFile(wb, 'plantilla_catalogo_farmacia.xlsx')
  }

  const procesarArchivo = async (file: File) => {
    setReporte(null)
    if (file.size > MAX_BYTES) { toast.error(`Archivo demasiado grande (máx ${MAX_BYTES / 1024 / 1024} MB)`); return }
    setParsing(true)
    try {
      const wb = XLSX.read(await file.arrayBuffer())
      const ws = wb.Sheets[wb.SheetNames[0]]
      const crudas = XLSX.utils.sheet_to_json<Record<string, any>>(ws, { defval: '' })
      if (crudas.length === 0) { toast.error('El archivo no tiene filas'); setFilas([]); setParsing(false); return }
      if (crudas.length > MAX_FILAS) { toast.error(`Demasiadas filas (${crudas.length}); máx ${MAX_FILAS}. Divide el archivo.`); setFilas([]); setParsing(false); return }

      // mapa encabezado-archivo → campo
      const mapa: Record<string, string> = {}
      for (const h of Object.keys(crudas[0])) {
        const hn = norm(h)
        for (const [campo, alias] of Object.entries(COLUMNAS)) if (alias.includes(hn)) { mapa[h] = campo; break }
      }
      if (!Object.values(mapa).includes('nombre_medicamento')) {
        toast.error('Falta la columna obligatoria "nombre_medicamento" (revisa los encabezados).')
        setFilas([]); setParsing(false); return
      }

      const parseadas: Fila[] = crudas.map((cruda) => {
        const raw: Record<string, string> = {}
        for (const [h, campo] of Object.entries(mapa)) raw[campo] = String(cruda[h] ?? '').trim()
        const e: string[] = []
        if (!raw.nombre_medicamento) e.push('nombre vacío')
        if (!esNumero(raw.stock_actual ?? '')) e.push('stock no numérico')
        if (!esNumero(raw.precio_unitario ?? '')) e.push('precio no numérico')
        if (!esEntero(raw.stock_minimo ?? '')) e.push('stock_minimo no entero')
        if (!esFecha(raw.fecha_vencimiento ?? '')) e.push('fecha inválida')
        return { raw, errores: e }
      })

      // DUPS INTRA-ARCHIVO: dos filas que normalizan a la misma clave (p.ej.
      // "Paracetamol 500mg" / "PARACETAMOL  500 MG"). Solo ADVERTIMOS en el preview y
      // enviamos TODAS las filas: el de-dup autoritativo es el pre-scan del RPC (única
      // fuente de normalización = la columna SQL) → anti-drift cliente↔servidor.
      const ultimaPorClave = new Map<string, number>()
      parseadas.forEach((f, idx) => { if (f.errores.length === 0) ultimaPorClave.set(claveNorm(f.raw.nombre_medicamento), idx) })
      parseadas.forEach((f, idx) => {
        if (f.errores.length === 0) {
          const k = claveNorm(f.raw.nombre_medicamento)
          if (ultimaPorClave.get(k) !== idx) f.warn = `duplica fila ${(ultimaPorClave.get(k) as number) + 1} (el servidor usa la última)`
        }
      })

      setFilas(parseadas)
      setNombreArchivo(file.name)
    } catch (err) {
      console.error(err); toast.error('No se pudo leer el archivo (.xlsx/.csv válido).'); setFilas([])
    } finally { setParsing(false) }
  }

  const importar = async () => {
    if (!farmaciaId) { toast.error('Selecciona la sucursal destino'); return }
    if (validas.length === 0) { toast.error('No hay filas válidas'); return }
    setCargando(true)
    const acc = { insertadas: 0, actualizadas: 0, rechazadas: [] as { fila: number; motivo: string }[] }
    try {
      // chunking: lotes de CHUNK filas para no exceder el statement timeout
      for (let off = 0; off < validas.length; off += CHUNK) {
        const lote = validas.slice(off, off + CHUNK).map((f) => f.raw)
        const { data, error } = await supabase.rpc('cargar_catalogo_farmacia', { p_farmacia_id: Number(farmaciaId), p_rows: lote })
        if (error) {
          // el RPC gatea farmacia∈empresa + inventario_editar: surfaceamos su mensaje con gracia.
          // Fallo a media subida: mostramos el progreso PARCIAL ya guardado + que reintentar es seguro.
          setReporte({ ...acc, error: `${error.message || 'Error en el lote'} (se procesaron ${off} fila(s) antes del fallo; reintentar es seguro: la carga es idempotente).` })
          toast.error(error.message || 'No autorizado para cargar en esta sucursal')
          setCargando(false); return
        }
        acc.insertadas += (data?.insertadas ?? 0)
        acc.actualizadas += (data?.actualizadas ?? 0)
        for (const r of (data?.rechazadas ?? [])) acc.rechazadas.push({ fila: off + r.fila, motivo: r.motivo })
      }
      setReporte(acc)
      toast.success(`Catálogo cargado: ${acc.insertadas} nuevas, ${acc.actualizadas} actualizadas` + (acc.rechazadas.length ? `, ${acc.rechazadas.length} rechazadas` : ''))
      onImported?.()
    } catch (err: any) {
      toast.error(err.message || 'Error en la carga')
    } finally { setCargando(false) }
  }

  const cerrar = () => { setFilas([]); setNombreArchivo(''); setReporte(null); onClose() }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && cerrar()}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><FileSpreadsheet className="w-5 h-5" /> Importar catálogo (Excel / CSV)</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">Descarga la plantilla, llénala y súbela. Re-subir actualiza por nombre (no duplica). El stock en blanco conserva el existente.</p>

          {/* sucursal destino (solo tus sucursales) */}
          <div>
            <label className="text-sm text-muted-foreground mb-1 block">Sucursal destino</label>
            {sucursales.length === 0 ? (
              <p className="text-sm text-amber-600">No tienes sucursales. Crea una sucursal antes de cargar catálogo.</p>
            ) : (
              <select value={farmaciaId} onChange={(e) => setFarmaciaId(e.target.value)} className="w-full p-2 border rounded-lg">
                <option value="">Seleccionar sucursal…</option>
                {sucursales.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
              </select>
            )}
          </div>

          <div className="flex flex-col sm:flex-row gap-3">
            <Button variant="outline" className="flex-1" onClick={descargarPlantilla}><Download className="w-4 h-4 mr-2" />1. Plantilla</Button>
            <label className="flex-1">
              <input type="file" accept=".xlsx,.xls,.csv" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) procesarArchivo(f); e.target.value = '' }} disabled={sucursales.length === 0} />
              <span className="inline-flex w-full items-center justify-center gap-2 rounded-md border bg-background px-4 py-2 text-sm font-medium cursor-pointer hover:bg-accent">
                {parsing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}2. Subir archivo
              </span>
            </label>
          </div>
          <p className="text-xs text-muted-foreground"><strong>nombre_medicamento</strong> obligatoria. Opcionales: presentacion, descripcion, laboratorio, stock_actual, stock_minimo, precio_unitario, fecha_vencimiento, activo (si/no). Máx {MAX_FILAS} filas / {MAX_BYTES / 1024 / 1024} MB.</p>

          {filas.length > 0 && !reporte && (
            <div className="space-y-3">
              <div className="flex items-center gap-4 text-sm">
                <span className="flex items-center gap-1 text-emerald-600 font-medium"><CheckCircle className="w-4 h-4" /> {validas.length} válidas</span>
                {invalidas.length > 0 && <span className="flex items-center gap-1 text-amber-600 font-medium"><AlertTriangle className="w-4 h-4" /> {invalidas.length} con error (se omiten)</span>}
                {validas.some((f) => f.warn) && <span className="text-blue-600 font-medium">{validas.filter((f) => f.warn).length} duplicada(s) (servidor usa la última)</span>}
                <span className="text-muted-foreground ml-auto truncate max-w-[40%]">{nombreArchivo}</span>
              </div>
              <div className="border rounded-lg overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50"><tr><th className="text-left p-2">Medicamento</th><th className="text-left p-2">Stock</th><th className="text-left p-2">Precio</th><th className="text-left p-2">Estado</th></tr></thead>
                  <tbody>
                    {filas.slice(0, 10).map((f, i) => (
                      <tr key={i} className="border-t">
                        <td className="p-2 truncate max-w-[200px]">{f.raw.nombre_medicamento || <em className="text-muted-foreground">(sin nombre)</em>}</td>
                        <td className="p-2">{f.raw.stock_actual || '—'}</td>
                        <td className="p-2">{f.raw.precio_unitario || '—'}</td>
                        <td className="p-2">{f.errores.length ? <span className="text-amber-600 text-xs">{f.errores.join(', ')}</span> : f.warn ? <span className="text-blue-600 text-xs">{f.warn}</span> : <span className="text-emerald-600">OK</span>}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {filas.length > 10 && <p className="text-xs text-muted-foreground p-2 bg-muted/30">… y {filas.length - 10} fila(s) más</p>}
              </div>
            </div>
          )}

          {/* reporte del servidor (autoridad) */}
          {reporte && (
            <div className="border rounded-lg p-3 text-sm space-y-1 bg-muted/30">
              <p className="font-medium">Reporte del servidor</p>
              {reporte.error && <p className="text-red-600 text-xs">⚠️ {reporte.error}</p>}
              <p className="text-emerald-600">{reporte.insertadas} nuevas · {reporte.actualizadas} actualizadas</p>
              {reporte.rechazadas.length > 0 && (
                <details><summary className="text-amber-600 cursor-pointer">{reporte.rechazadas.length} rechazadas</summary>
                  <ul className="text-xs mt-1 max-h-32 overflow-y-auto">{reporte.rechazadas.map((r, i) => <li key={i}>fila {r.fila}: {r.motivo}</li>)}</ul>
                </details>
              )}
            </div>
          )}

          <div className="flex gap-3 pt-2">
            <Button variant="outline" className="flex-1" onClick={cerrar} disabled={cargando}>{reporte ? 'Cerrar' : 'Cancelar'}</Button>
            {!reporte && (
              <Button className="flex-1 bg-[#B45309] hover:bg-[#92400e]" onClick={importar} disabled={cargando || validas.length === 0 || !farmaciaId}>
                {cargando ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Upload className="w-4 h-4 mr-2" />}Cargar {validas.length || ''}
              </Button>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
