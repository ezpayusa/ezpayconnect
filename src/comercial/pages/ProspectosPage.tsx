import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { listarProspectos, listarEstados, asesoresConNombre, mapaAsesores, nombreAsesor,
  type Prospecto, type ItemCatalogo, type AsesorConNombre } from '../lib/api'
import { reportarError } from '../lib/reportarError'

// Cartera. MISMA pantalla para asesor y supervisor: el conjunto lo ensancha la RLS
// (asesores_a_cargo()), no un if del cliente. Lo único que cambia es que el supervisor ve la
// columna "Asesor" — para el asesor sería siempre él mismo.
//
// Dos pantallas casi iguales serían dos lugares donde aplicar la próxima regla, y la segunda
// siempre se olvida.
export default function ProspectosPage() {
  const { perfil } = useAuth()
  const esSupervisor = perfil?.rol === 'supervisor_comercial'
  const [filas, setFilas] = useState<Prospecto[]>([])
  const [estados, setEstados] = useState<ItemCatalogo[]>([])
  const [nombres, setNombres] = useState<Map<string, AsesorConNombre>>(new Map())
  const [cargando, setCargando] = useState(true)

  const cargar = async () => {
    setCargando(true)
    const [{ data, error }, cat, nom] = await Promise.all([listarProspectos(), listarEstados(), asesoresConNombre()])
    if (error) reportarError(error)
    else setFilas((data ?? []) as unknown as Prospecto[])
    if (cat.data) setEstados(cat.data as ItemCatalogo[])
    if (nom.error) reportarError(nom.error); else setNombres(mapaAsesores(nom.data as AsesorConNombre[] | null))
    setCargando(false)
  }

  useEffect(() => { void cargar() }, [])

  const etiqueta = (codigo: string) => estados.find(e => e.codigo === codigo)?.etiqueta ?? codigo

  if (cargando) return <p className="text-sm text-gray-500">Cargando cartera…</p>

  return (
    <div>
      <div className="mb-3 flex items-baseline justify-between">
        <h1 className="text-lg font-semibold text-gray-900">
          {esSupervisor ? 'Cartera del equipo' : 'Mis prospectos'}
        </h1>
        <span className="text-xs text-gray-500">{filas.length} prospecto(s)</span>
      </div>

      {filas.length === 0 ? (
        <p className="rounded-lg border border-dashed border-gray-300 bg-white p-6 text-sm text-gray-600">
          Todavía no tenés prospectos asignados. Los carga el administrador de tu país.
        </p>
      ) : (
        <ul className="space-y-2">
          {filas.map(p => (
            <li key={p.id}>
              <Link
                to={`/comercial/prospectos/${p.id}`}
                className="block rounded-lg border bg-white p-3 hover:border-[#1E5C8E]"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate font-medium text-gray-900">{p.nombre}</p>
                    <p className="mt-0.5 text-xs text-gray-500">
                      {p.tipo.replace(/_/g, ' ')}
                      {/* "sin asesor" queda SOLO para asesor_id NULL de verdad. Un asesor fuera del
                          alcance del llamante dice "asesor no visible": son dos cosas distintas y
                          confundirlas fue lo que escondio el bug de RLS de perfiles. */}
                      {esSupervisor && (
                        <> · <span className="text-gray-700">{nombreAsesor(p.asesor_id, nombres)}</span></>
                      )}
                    </p>
                  </div>
                  <span className="shrink-0 rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-700">
                    {etiqueta(p.estado_pipeline)}
                  </span>
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
