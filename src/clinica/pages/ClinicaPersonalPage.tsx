import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { useClinicaAuth } from '@/clinica/hooks/useClinicaAuth'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import {
  Users,
  Stethoscope,
  UserCog,
  User,
  RefreshCw,
  ArrowLeft,
} from 'lucide-react'

interface PersonalItem {
  id: string
  nombre_completo: string
  email: string
  rol: string
  telefono: string | null
  especialidad: string | null
  es_principal: boolean
}

export default function ClinicaPersonalPage() {
  const navigate = useNavigate()
  const { clinica } = useClinicaAuth()
  const [personal, setPersonal] = useState<PersonalItem[]>([])
  const [loading, setLoading] = useState(true)

  const cargarPersonal = async () => {
    if (!clinica) return
    setLoading(true)

    try {
      // RPC SECURITY DEFINER: devuelve el personal de la clínica revalidando que
      // el caller pertenece a ella. (perfiles SELECT está restringido a "propio";
      // por eso NO se lee perfiles directo, que solo devolvería al propio admin.)
      const { data, error } = await supabase
        .rpc('obtener_personal_clinica', { p_clinica_id: clinica.id })

      if (error) {
        console.error('Error cargando personal:', error)
        toast.error('Error cargando personal')
        setPersonal([])
        setLoading(false)
        return
      }

      const combined = (data || []).map((r: any) => ({
        id: r.medico_id,
        nombre_completo: r.nombre_completo,
        email: r.email,
        rol: r.rol,
        telefono: r.telefono,
        especialidad: r.especialidad || null,
        es_principal: r.es_principal || false,
      }))

      setPersonal(combined)
    } catch (error) {
      console.error('Error cargando personal:', error)
      toast.error('Error cargando personal')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    cargarPersonal()
  }, [clinica])

  const getRolBadge = (rol: string) => {
    switch (rol) {
      case 'medico': return <Badge className="bg-blue-100 text-blue-700">Médico</Badge>
      case 'admin_clinica': return <Badge className="bg-emerald-100 text-emerald-700">Admin</Badge>
      case 'secretaria': return <Badge className="bg-purple-100 text-purple-700">Secretaria</Badge>
      case 'asistente': return <Badge className="bg-amber-100 text-amber-700">Asistente</Badge>
      default: return <Badge variant="secondary">{rol}</Badge>
    }
  }

  const getRolIcon = (rol: string) => {
    switch (rol) {
      case 'medico': return <Stethoscope className="w-4 h-4" />
      case 'admin_clinica': return <UserCog className="w-4 h-4" />
      default: return <User className="w-4 h-4" />
    }
  }

  return (
    <div className="max-w-5xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/clinica')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Users className="w-6 h-6 text-[#1E5C8E]" />
              Personal de la Clínica
            </h1>
            <p className="text-sm text-muted-foreground">{clinica?.nombre}</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={cargarPersonal}>
            <RefreshCw className="h-4 w-4 mr-2" /> Recargar
          </Button>
          <Button onClick={() => navigate('/clinica/invitar-medico')} className="bg-[#1E5C8E] hover:bg-[#164a70]">
            <Stethoscope className="h-4 w-4 mr-2" /> Invitar Médico
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Equipo ({personal.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center p-8">Cargando...</div>
          ) : personal.length === 0 ? (
            <div className="text-center py-8 text-gray-500">
              <Users className="w-12 h-12 mx-auto mb-3 text-gray-300" />
              <p>No hay personal registrado</p>
              <p className="text-sm">Invita médicos y staff para comenzar</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-3 px-4">Nombre</th>
                    <th className="text-left py-3 px-4">Email</th>
                    <th className="text-left py-3 px-4">Rol</th>
                    <th className="text-left py-3 px-4">Especialidad</th>
                    <th className="text-left py-3 px-4">Principal</th>
                  </tr>
                </thead>
                <tbody>
                  {personal.map((p) => (
                    <tr key={p.id} className="border-b hover:bg-gray-50">
                      <td className="py-3 px-4 font-medium flex items-center gap-2">
                        {getRolIcon(p.rol)}
                        {p.nombre_completo}
                      </td>
                      <td className="py-3 px-4">{p.email}</td>
                      <td className="py-3 px-4">{getRolBadge(p.rol)}</td>
                      <td className="py-3 px-4">{p.especialidad || '-'}</td>
                      <td className="py-3 px-4">
                        {p.es_principal ? (
                          <Badge className="bg-emerald-100 text-emerald-700">Sí</Badge>
                        ) : (
                          <span className="text-gray-400">-</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
