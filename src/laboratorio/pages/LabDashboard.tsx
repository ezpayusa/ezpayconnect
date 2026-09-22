import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import { useLaboratorio } from '@/laboratorio/hooks/useLaboratorio'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent } from '@/components/ui/card'
import { ClipboardList, Clock, FlaskConical, CheckCircle2, Building2, UserPlus } from 'lucide-react'

// ############################################################################################
// Conteo de las tarjetas del dashboard
// ############################################################################################
// SE CUENTA POR EXAMEN, NO POR ORDEN. El conteo viejo hacía `ordenes.filter(o => o.estado === …)`
// y `OrdenAgrupada` NO TIENE `estado`: el estado vive en cada `items[]`. El filtro comparaba
// contra `undefined` y devolvía siempre cero, así que las tres tarjetas mostraban 0 aunque la
// bandeja tuviera órdenes activas.
//
// EL COMPILADOR LO VENÍA GRITANDO. Esas 3 líneas producían 4 errores
// `TS2339: Property 'estado' does not exist on type 'OrdenAgrupada'` — estaban adentro del
// baseline de 82 de `tsc -p tsconfig.app.json`, o sea contadas como deuda tolerada y por eso
// invisibles. Arreglarlo bajó el baseline a 78. Un baseline es un techo, no una alfombra: lo que
// entra ahí deja de leerse.
//
// Además una orden no tiene UN estado: sus exámenes avanzan por separado. Un pedido de 3 estudios
// puede tener uno entregado y dos en proceso, así que "por orden" ni siquiera es una pregunta bien
// formada. La unidad correcta es el examen.
//
// LOS 5 VALORES DEL ENUM `examen_estado` ESTÁN CUBIERTOS, medidos contra el tipo vivo:
//   pendiente · recibida · en_proceso · revision · completado
// `revision` no estaba contemplado en el conteo viejo y se suma a "En proceso": el examen está en
// el laboratorio y todavía no salió. El test de este archivo verifica que los tres baldes
// PARTICIONEN el total — si mañana aparece un sexto estado, falla en vez de tragárselo.
export interface ConteoExamenes {
  pendientes: number
  enProceso: number
  completadas: number
}

const EN_PROCESO = new Set(['recibida', 'en_proceso', 'revision'])

export function contarExamenes(ordenes: { items: { estado: string }[] }[]): ConteoExamenes {
  const todosLosItems = ordenes.flatMap((o) => o.items)
  return {
    pendientes: todosLosItems.filter((i) => i.estado === 'pendiente').length,
    enProceso: todosLosItems.filter((i) => EN_PROCESO.has(i.estado)).length,
    completadas: todosLosItems.filter((i) => i.estado === 'completado').length,
  }
}

export default function LabDashboard() {
  const { empresa } = useProveedorAuth()
  const { ordenes, afiliaciones, invitaciones, fetchAfiliaciones, fetchInvitaciones } = useLaboratorio()

  useEffect(() => { fetchAfiliaciones(); fetchInvitaciones() }, [fetchAfiliaciones, fetchInvitaciones])

  const { pendientes, enProceso, completadas } = contarExamenes(ordenes)

  const stats = [
    { label: 'Pendientes de recibir', value: pendientes, icon: Clock, color: 'text-amber-600', to: '/laboratorio/ordenes' },
    { label: 'En proceso', value: enProceso, icon: FlaskConical, color: 'text-purple-600', to: '/laboratorio/ordenes' },
    { label: 'Completadas', value: completadas, icon: CheckCircle2, color: 'text-green-600', to: '/laboratorio/ordenes' },
    { label: 'Clínicas afiliadas', value: afiliaciones.length, icon: Building2, color: 'text-[#0E7C6B]', to: '/laboratorio/afiliaciones' },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#0c2a26]">{empresa?.nombre_empresa || 'Laboratorio'}</h1>
        <p className="text-sm text-muted-foreground">Resumen de tu actividad.</p>
      </div>

      {invitaciones.length > 0 && (
        <Link to="/laboratorio/afiliaciones">
          <div className="p-4 bg-amber-50 border border-amber-200 rounded-lg flex items-center gap-3 hover:bg-amber-100 transition-colors">
            <Building2 className="h-5 w-5 text-amber-600" />
            <span className="text-sm font-medium text-amber-800">
              Tienes {invitaciones.length} invitación(es) de clínica pendiente(s). Toca para revisar.
            </span>
          </div>
        </Link>
      )}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((s) => (
          <Link key={s.label} to={s.to}>
            <Card className="hover:shadow-md transition-shadow">
              <CardContent className="p-5">
                <s.icon className={`h-6 w-6 ${s.color} mb-2`} />
                <p className="text-2xl font-bold">{s.value}</p>
                <p className="text-xs text-muted-foreground">{s.label}</p>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Link to="/laboratorio/ordenes">
          <Card className="hover:shadow-md transition-shadow">
            <CardContent className="p-5 flex items-center gap-3">
              <ClipboardList className="h-6 w-6 text-[#0E7C6B]" />
              <div><p className="font-medium">Ver órdenes de examen</p><p className="text-xs text-muted-foreground">Recibe y sube resultados</p></div>
            </CardContent>
          </Card>
        </Link>
        <Link to="/laboratorio/walk-in">
          <Card className="hover:shadow-md transition-shadow">
            <CardContent className="p-5 flex items-center gap-3">
              <UserPlus className="h-6 w-6 text-[#0E7C6B]" />
              <div><p className="font-medium">Registrar walk-in</p><p className="text-xs text-muted-foreground">Paciente sin orden médica</p></div>
            </CardContent>
          </Card>
        </Link>
      </div>
    </div>
  )
}
