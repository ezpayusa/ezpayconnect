import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { Users, Loader2, AlertTriangle, Plus, UserMinus, MapPin, Shield } from 'lucide-react'

interface Equipo { id: string; nombre: string; zona: string | null; supervisor_id: string | null }
interface Cuenta { id: string; nombre_completo: string; email: string; rol_en_empresa: string; equipo_id: string | null }

export default function EquiposPage() {
  const { empresa, rol, puede } = useProveedorAuth()
  const [equipos, setEquipos] = useState<Equipo[]>([])
  const [cuentas, setCuentas] = useState<Cuenta[]>([])
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState(false)
  // Crear equipo (solo admin)
  const [nombre, setNombre] = useState('')
  const [zona, setZona] = useState('')
  const [supervisorId, setSupervisorId] = useState('')

  const esAdmin = rol === 'admin' || rol === 'editor'

  const cargar = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const [{ data: eq }, { data: cu }] = await Promise.all([
      supabase.from('equipos_visitadores').select('id, nombre, zona, supervisor_id').eq('empresa_id', empresa.id).order('nombre'),
      supabase.from('cuentas_proveedor').select('id, nombre_completo, email, rol_en_empresa, equipo_id').eq('empresa_id', empresa.id),
    ])
    setEquipos((eq || []) as Equipo[])
    setCuentas((cu || []) as Cuenta[])
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => { cargar() }, [cargar])

  const supervisores = cuentas.filter((c) => c.rol_en_empresa === 'supervisor')
  const visitadores = cuentas.filter((c) => c.rol_en_empresa === 'visitador_medico')
  const sinEquipo = visitadores.filter((v) => !v.equipo_id)
  const nombreCuenta = (id: string | null) => cuentas.find((c) => c.id === id)?.nombre_completo || '—'

  const crearEquipo = async () => {
    if (!nombre.trim()) { toast.error('Ponle un nombre al equipo'); return }
    setGuardando(true)
    const { error } = await supabase.from('equipos_visitadores').insert({
      empresa_id: empresa!.id,
      nombre: nombre.trim(),
      zona: zona.trim() || null,
      supervisor_id: supervisorId || null,
    })
    setGuardando(false)
    if (error) { toast.error('Error creando equipo: ' + error.message); return }
    toast.success('Equipo creado')
    setNombre(''); setZona(''); setSupervisorId('')
    cargar()
  }

  const asignar = async (visitadorId: string, equipoId: string | null) => {
    const { error } = await supabase.rpc('asignar_visitador_equipo', {
      p_visitador_id: visitadorId,
      p_equipo_id: equipoId,
    })
    if (error) { toast.error(error.message || 'No se pudo asignar'); return }
    toast.success(equipoId ? 'Visitador asignado' : 'Visitador quitado del equipo')
    cargar()
  }

  if (!puede('visitadores.gestionar')) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">No tienes permiso para gestionar equipos.</p>
      </div>
    )
  }

  return (
    <div className="p-4 max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2"><Users className="w-6 h-6" /> Equipos de visitadores</h1>
        <p className="text-muted-foreground">
          {esAdmin
            ? 'Crea equipos, asigna un supervisor y reparte los visitadores. Cada supervisor solo verá su propio equipo.'
            : 'Gestiona los visitadores de tus equipos. No ves los equipos de otros supervisores.'}
        </p>
      </div>

      {/* Crear equipo — solo admin */}
      {esAdmin && (
        <Card>
          <CardContent className="p-4 space-y-3">
            <p className="text-sm font-semibold flex items-center gap-2"><Plus className="w-4 h-4" /> Nuevo equipo</p>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <Input placeholder="Nombre del equipo" value={nombre} onChange={(e) => setNombre(e.target.value)} />
              <Input placeholder="Zona (opcional)" value={zona} onChange={(e) => setZona(e.target.value)} />
              <select className="h-10 rounded-md border border-input bg-background px-3 text-sm" value={supervisorId} onChange={(e) => setSupervisorId(e.target.value)}>
                <option value="">Sin supervisor</option>
                {supervisores.map((s) => <option key={s.id} value={s.id}>{s.nombre_completo}</option>)}
              </select>
            </div>
            <Button onClick={crearEquipo} disabled={guardando} className="bg-[#1E5C8E] hover:bg-[#164a70]">
              {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Plus className="h-4 w-4 mr-2" />}
              Crear equipo
            </Button>
            {supervisores.length === 0 && (
              <p className="text-xs text-amber-600">
                No hay supervisores aún. Invita o asigna el rol "Supervisor de visitadores" en Personal y Roles.
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-slate-400" /></div>
      ) : (
        <div className="space-y-4">
          {equipos.map((eq) => {
            const miembros = visitadores.filter((v) => v.equipo_id === eq.id)
            return (
              <Card key={eq.id}>
                <CardHeader className="pb-2">
                  <CardTitle className="text-lg flex flex-wrap items-center gap-2">
                    {eq.nombre}
                    {eq.zona && <Badge variant="outline" className="text-xs"><MapPin className="w-3 h-3 mr-1" />{eq.zona}</Badge>}
                    <Badge variant="secondary" className="text-xs"><Shield className="w-3 h-3 mr-1" />{nombreCuenta(eq.supervisor_id)}</Badge>
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  {miembros.length === 0 ? (
                    <p className="text-sm text-muted-foreground">Sin visitadores asignados.</p>
                  ) : (
                    <div className="space-y-2">
                      {miembros.map((m) => (
                        <div key={m.id} className="flex items-center justify-between border rounded-lg p-2">
                          <div className="text-sm">
                            <p className="font-medium">{m.nombre_completo}</p>
                            <p className="text-xs text-muted-foreground">{m.email}</p>
                          </div>
                          <Button size="sm" variant="ghost" className="text-red-600" onClick={() => asignar(m.id, null)}>
                            <UserMinus className="w-3.5 h-3.5 mr-1" /> Quitar
                          </Button>
                        </div>
                      ))}
                    </div>
                  )}

                  {/* Agregar del pool libre */}
                  {sinEquipo.length > 0 && (
                    <div className="flex items-center gap-2 pt-1">
                      <select
                        className="h-9 rounded-md border border-input bg-background px-3 text-sm flex-1"
                        defaultValue=""
                        onChange={(e) => { if (e.target.value) { asignar(e.target.value, eq.id); e.target.value = '' } }}
                      >
                        <option value="">+ Agregar visitador (sin equipo)…</option>
                        {sinEquipo.map((v) => <option key={v.id} value={v.id}>{v.nombre_completo}</option>)}
                      </select>
                    </div>
                  )}
                </CardContent>
              </Card>
            )
          })}

          {equipos.length === 0 && (
            <Card className="bg-gray-50 border-dashed">
              <CardContent className="p-8 text-center text-muted-foreground">
                <Users className="h-10 w-10 mx-auto mb-3 text-gray-300" />
                <p>{esAdmin ? 'Aún no hay equipos. Crea el primero arriba.' : 'No tienes equipos asignados todavía.'}</p>
              </CardContent>
            </Card>
          )}

          {/* Pool sin equipo (informativo) */}
          {sinEquipo.length > 0 && (
            <Card className="border-dashed">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm text-muted-foreground">Visitadores sin equipo ({sinEquipo.length})</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-wrap gap-2">
                {sinEquipo.map((v) => (
                  <Badge key={v.id} variant="outline">{v.nombre_completo}</Badge>
                ))}
              </CardContent>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
