import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { CheckCircle2, XCircle } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { reportarError } from '@/comercial/lib/reportarError'

// Clínicas del país, SOLO LECTURA. Cuelga del AdminLayout con el AdminRoute que ya confina al
// admin_pais a su propio /pais/{su pais_id}.
//
// EL BOTÓN EXISTÍA DESDE EL 7-jun (commit 62b3ad8) Y NUNCA TUVO PANTALLA: "Ver Clínicas" de
// PaisDashboardPage navegaba a esta ruta, que no estaba montada, y caía en NotFoundPage sin error
// visible. Esta pantalla es el destino que le faltaba.
//
// VA A LA TABLA, NO A listar_clinicas_por_pais. La RPC devuelve sólo id/nombre/pais_id y quedó
// acotada a su único consumidor real (AgendarCitaModal) en la mig 296. Acá hacen falta `activa`,
// `direccion` y `telefono`, y la RLS de `clinicas` ya hace el scoping exacto que necesitamos:
//   "Admin ve clinicas de su pais": super_admin OR (admin_pais AND pais_id = get_auth_user_pais_id())
// Es además lo que hacen el resto de las páginas país-scoped del admin: consultan tablas con RLS,
// no RPCs propias.
//
// El .eq('pais_id', paisId) es un SELECTOR DE VISTA, no un permiso: esta ruta está parametrizada
// por :paisId y un super_admin ve varios países, así que el filtro elige CUÁL mirar. Sólo puede
// achicar lo que la policy ya permitió — si un admin de otro país forzara la URL, la policy le
// devuelve 0 filas igual.
type ClinicaDelPais = {
  id: string
  nombre: string
  direccion: string | null
  telefono: string | null
  activa: boolean | null
}

const COLUMNAS = 'id, nombre, direccion, telefono, activa'

export default function ClinicasPaisPage() {
  const { paisId = '' } = useParams()
  const [filas, setFilas] = useState<ClinicaDelPais[]>([])
  const [cargando, setCargando] = useState(true)

  const cargar = async () => {
    setCargando(true)
    const { data, error } = await supabase
      .from('clinicas')
      .select(COLUMNAS)
      .eq('pais_id', paisId)
      .order('nombre')

    if (error) reportarError(error)
    else setFilas((data ?? []) as unknown as ClinicaDelPais[])
    setCargando(false)
  }

  useEffect(() => { void cargar() }, [paisId])

  return (
    <div className="space-y-5 p-4">
      <h1 className="text-xl font-semibold text-gray-900">Clínicas del país</h1>

      <section className="rounded-lg border bg-white p-4">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold text-gray-900">Clínicas</h2>
          <span className="text-xs text-gray-500">{filas.length}</span>
        </div>
        {cargando ? (
          <p className="mt-2 text-sm text-gray-500">Cargando…</p>
        ) : filas.length === 0 ? (
          // Una tabla vacía sin explicación se lee como un error de carga. Esto dice qué pasa.
          <p className="mt-2 text-sm text-gray-500">Todavía no hay clínicas en este país.</p>
        ) : (
          <table className="mt-3 w-full text-sm">
            <thead>
              <tr className="border-b text-left text-xs uppercase text-gray-500">
                <th className="py-2">Nombre</th><th>Dirección</th><th>Teléfono</th><th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {filas.map(c => (
                <tr key={c.id} className="border-b last:border-0">
                  <td className="py-2 font-medium text-gray-900">{c.nombre}</td>
                  {/* Un campo vacío se pinta como guión y no como celda en blanco: en blanco no se
                      distingue de una columna que no cargó. */}
                  <td className="text-gray-600">{c.direccion || '—'}</td>
                  <td className="text-gray-600">{c.telefono || '—'}</td>
                  <td>
                    <span
                      data-testid={`clinica-estado-${c.id}`}
                      className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs ${
                        c.activa ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-600'}`}
                    >
                      {c.activa ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                      {c.activa ? 'activa' : 'inactiva'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  )
}
