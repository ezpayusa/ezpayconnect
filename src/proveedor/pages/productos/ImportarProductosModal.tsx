import { useState } from 'react'
import * as XLSX from 'xlsx'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'
import { Download, Upload, FileSpreadsheet, CheckCircle, AlertTriangle, Loader2 } from 'lucide-react'
import { useProductosEmpresa } from '@/proveedor/hooks/useProductosEmpresa'

interface Props {
  open: boolean
  onClose: () => void
  onImported?: () => void
}

interface FilaParseada {
  nombre_producto: string
  principio_activo: string
  presentacion: string
  concentracion: string
  categoria: string
  precio_unitario: number
  moneda: string
  stock_disponible: number
  requiere_receta: boolean
  _errores: string[]
}

// Normaliza un encabezado: minúsculas, sin acentos, sin espacios extra
const norm = (s: string) =>
  s
    .toString()
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/\s+/g, ' ')

// Alias de columnas aceptados -> campo interno
const COLUMNAS: Record<string, string[]> = {
  nombre_producto: ['nombre_producto', 'nombre del producto', 'nombre', 'producto'],
  precio_unitario: ['precio_unitario', 'precio unitario', 'precio'],
  principio_activo: ['principio_activo', 'principio activo', 'principio'],
  presentacion: ['presentacion', 'presentación'],
  concentracion: ['concentracion', 'concentración'],
  categoria: ['categoria', 'categoría'],
  stock_disponible: ['stock_disponible', 'stock disponible', 'stock', 'existencia', 'existencias'],
  requiere_receta: ['requiere_receta', 'requiere receta', 'receta'],
  moneda: ['moneda'],
}

const TEMPLATE_HEADERS = [
  'nombre_producto',
  'precio_unitario',
  'principio_activo',
  'presentacion',
  'concentracion',
  'categoria',
  'stock_disponible',
  'requiere_receta',
  'moneda',
]

const TEMPLATE_EJEMPLO = [
  'Paracetamol 500mg',
  12.5,
  'Paracetamol',
  'Tabletas',
  '500 mg',
  'Analgésicos',
  100,
  'no',
  'GTQ',
]

const truthy = (v: any) =>
  ['si', 'sí', 'true', '1', 'x', 'y', 'yes', 'verdadero'].includes(norm(String(v ?? '')))

export default function ImportarProductosModal({ open, onClose, onImported }: Props) {
  const { crearProductosMasivo, saving } = useProductosEmpresa()
  const [filas, setFilas] = useState<FilaParseada[]>([])
  const [nombreArchivo, setNombreArchivo] = useState('')
  const [parsing, setParsing] = useState(false)

  const validas = filas.filter((f) => f._errores.length === 0)
  const invalidas = filas.filter((f) => f._errores.length > 0)

  const descargarPlantilla = () => {
    const ws = XLSX.utils.aoa_to_sheet([TEMPLATE_HEADERS, TEMPLATE_EJEMPLO])
    ws['!cols'] = TEMPLATE_HEADERS.map(() => ({ wch: 18 }))
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, ws, 'Productos')
    XLSX.writeFile(wb, 'plantilla_productos_ezpayconnect.xlsx')
  }

  const procesarArchivo = async (file: File) => {
    setParsing(true)
    try {
      const buffer = await file.arrayBuffer()
      const wb = XLSX.read(buffer)
      const ws = wb.Sheets[wb.SheetNames[0]]
      const crudas = XLSX.utils.sheet_to_json<Record<string, any>>(ws, { defval: '' })

      if (crudas.length === 0) {
        toast.error('El archivo no tiene filas de datos')
        setFilas([])
        setParsing(false)
        return
      }

      // Construir mapa: encabezado-del-archivo -> campo-interno
      const encabezados = Object.keys(crudas[0])
      const mapa: Record<string, string> = {}
      for (const h of encabezados) {
        const hn = norm(h)
        for (const [campo, alias] of Object.entries(COLUMNAS)) {
          if (alias.includes(hn)) {
            mapa[h] = campo
            break
          }
        }
      }

      const parseadas: FilaParseada[] = crudas.map((raw) => {
        const obj: any = {}
        for (const [h, campo] of Object.entries(mapa)) {
          obj[campo] = raw[h]
        }

        const errores: string[] = []
        const nombre = String(obj.nombre_producto ?? '').trim()
        if (!nombre) errores.push('Falta nombre')

        const precioRaw = String(obj.precio_unitario ?? '').replace(',', '.').trim()
        const precio = parseFloat(precioRaw)
        if (precioRaw === '' || isNaN(precio)) errores.push('Precio inválido')

        const stock = parseInt(String(obj.stock_disponible ?? '0').trim()) || 0

        return {
          nombre_producto: nombre,
          principio_activo: String(obj.principio_activo ?? '').trim(),
          presentacion: String(obj.presentacion ?? '').trim(),
          concentracion: String(obj.concentracion ?? '').trim(),
          categoria: String(obj.categoria ?? '').trim(),
          precio_unitario: isNaN(precio) ? 0 : precio,
          moneda: String(obj.moneda ?? 'GTQ').trim().toUpperCase() || 'GTQ',
          stock_disponible: stock,
          requiere_receta: truthy(obj.requiere_receta),
          _errores: errores,
        }
      })

      setFilas(parseadas)
      setNombreArchivo(file.name)
    } catch (err) {
      console.error(err)
      toast.error('No se pudo leer el archivo. Verifica que sea un Excel (.xlsx) o CSV válido.')
      setFilas([])
    } finally {
      setParsing(false)
    }
  }

  const handleFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) procesarArchivo(file)
    e.target.value = ''
  }

  const importar = async () => {
    if (validas.length === 0) {
      toast.error('No hay filas válidas para importar')
      return
    }
    const { creados, error } = await crearProductosMasivo(validas)
    if (error) {
      toast.error('Error en la importación: ' + error)
      return
    }
    toast.success(`${creados} producto${creados !== 1 ? 's' : ''} importado${creados !== 1 ? 's' : ''}`)
    cerrar()
    onImported?.()
  }

  const cerrar = () => {
    setFilas([])
    setNombreArchivo('')
    onClose()
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && cerrar()}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileSpreadsheet className="w-5 h-5" />
            Importar productos (Excel / CSV)
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">
            Sube tu catálogo completo de una sola vez. Descarga la plantilla, llénala con tus
            productos y vuelve a subirla. Las imágenes se agregan después por producto.
          </p>

          {/* Paso 1: plantilla */}
          <div className="flex flex-col sm:flex-row gap-3">
            <Button variant="outline" className="flex-1" onClick={descargarPlantilla}>
              <Download className="w-4 h-4 mr-2" />
              1. Descargar plantilla
            </Button>
            <label className="flex-1">
              <input
                type="file"
                accept=".xlsx,.xls,.csv"
                className="hidden"
                onChange={handleFile}
              />
              <span className="inline-flex w-full items-center justify-center gap-2 rounded-md border border-input bg-background px-4 py-2 text-sm font-medium cursor-pointer hover:bg-accent transition-colors">
                {parsing ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Upload className="w-4 h-4" />
                )}
                2. Subir archivo lleno
              </span>
            </label>
          </div>

          <p className="text-xs text-muted-foreground">
            Columnas: <strong>nombre_producto</strong> y <strong>precio_unitario</strong> son
            obligatorias. Opcionales: principio_activo, presentacion, concentracion, categoria,
            stock_disponible, requiere_receta (si/no), moneda.
          </p>

          {/* Resumen + vista previa */}
          {filas.length > 0 && (
            <div className="space-y-3">
              <div className="flex items-center gap-4 text-sm">
                <span className="flex items-center gap-1 text-emerald-600 font-medium">
                  <CheckCircle className="w-4 h-4" /> {validas.length} válido{validas.length !== 1 ? 's' : ''}
                </span>
                {invalidas.length > 0 && (
                  <span className="flex items-center gap-1 text-amber-600 font-medium">
                    <AlertTriangle className="w-4 h-4" /> {invalidas.length} con error (se omitirán)
                  </span>
                )}
                <span className="text-muted-foreground ml-auto truncate max-w-[40%]">{nombreArchivo}</span>
              </div>

              <div className="border rounded-lg overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50">
                    <tr>
                      <th className="text-left p-2 font-medium">Producto</th>
                      <th className="text-left p-2 font-medium">Precio</th>
                      <th className="text-left p-2 font-medium">Stock</th>
                      <th className="text-left p-2 font-medium">Estado</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filas.slice(0, 8).map((f, i) => (
                      <tr key={i} className="border-t">
                        <td className="p-2 truncate max-w-[200px]">{f.nombre_producto || <em className="text-muted-foreground">(sin nombre)</em>}</td>
                        <td className="p-2">{f.moneda} {f.precio_unitario.toFixed(2)}</td>
                        <td className="p-2">{f.stock_disponible}</td>
                        <td className="p-2">
                          {f._errores.length === 0 ? (
                            <span className="text-emerald-600">OK</span>
                          ) : (
                            <span className="text-amber-600 text-xs">{f._errores.join(', ')}</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                {filas.length > 8 && (
                  <p className="text-xs text-muted-foreground p-2 bg-muted/30">
                    … y {filas.length - 8} fila{filas.length - 8 !== 1 ? 's' : ''} más
                  </p>
                )}
              </div>
            </div>
          )}

          <div className="flex gap-3 pt-2">
            <Button variant="outline" className="flex-1" onClick={cerrar} disabled={saving}>
              Cancelar
            </Button>
            <Button
              className="flex-1 bg-[#1E5C8E] hover:bg-[#164a70]"
              onClick={importar}
              disabled={saving || validas.length === 0}
            >
              {saving ? <Loader2 className="w-4 h-4 animate-spin mr-2" /> : <Upload className="w-4 h-4 mr-2" />}
              Importar {validas.length > 0 ? `${validas.length} producto${validas.length !== 1 ? 's' : ''}` : ''}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
