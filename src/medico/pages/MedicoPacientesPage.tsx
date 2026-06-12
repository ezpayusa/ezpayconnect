import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMedicoPacientes } from '@/medico/hooks/useMedicoPacientes'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Users,
  Search,
  User,
  Phone,
  Mail,
  Loader2,
  RefreshCw,
  FileText,
  ArrowRight,
} from 'lucide-react'

export default function MedicoPacientesPage() {
  const navigate = useNavigate()
  const { pacientes, loading, recargar } = useMedicoPacientes()
  const [busqueda, setBusqueda] = useState('')

  const pacientesFiltrados = pacientes.filter((p) => {
    const q = busqueda.toLowerCase()
    return (
      p.nombre.toLowerCase().includes(q) ||
      p.apellido.toLowerCase().includes(q) ||
      (p.telefono || '').includes(q) ||
      (p.email || '').toLowerCase().includes(q)
    )
  })

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[#1a2a3a] flex items-center gap-2">
            <Users className="h-7 w-7 text-[#1E5C8E]" />
            Mis Pacientes
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            {pacientes.length} pacientes registrados
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={recargar}>
          <RefreshCw className="h-4 w-4 mr-1" />
          Recargar
        </Button>
      </div>

      {/* Búsqueda */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          placeholder="Buscar por nombre, teléfono o email..."
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
          className="pl-9"
        />
      </div>

      {/* Listado */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {pacientesFiltrados.length === 0 ? (
          <div className="col-span-full text-center py-16 bg-white rounded-xl border border-dashed">
            <Users className="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p className="text-lg font-medium text-gray-500">
              {busqueda ? 'No se encontraron pacientes' : 'No tienes pacientes registrados'}
            </p>
          </div>
        ) : (
          pacientesFiltrados.map((p) => (
            <Card
              key={p.id}
              className="cursor-pointer transition-shadow hover:shadow-md"
              onClick={() => navigate(`/medico/pacientes/${p.id}/detalle`)}
            >
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-[#1E5C8E]/10 flex items-center justify-center">
                      <User className="h-5 w-5 text-[#1E5C8E]" />
                    </div>
                    <div>
                      <p className="font-medium">
                        {p.nombre} {p.apellido}
                      </p>
                      <div className="flex items-center gap-2 text-xs text-muted-foreground mt-0.5">
                        {p.telefono && (
                          <span className="flex items-center gap-1">
                            <Phone className="h-3 w-3" />
                            {p.telefono}
                          </span>
                        )}
                        {p.email && (
                          <span className="flex items-center gap-1">
                            <Mail className="h-3 w-3" />
                            {p.email}
                          </span>
                        )}
                      </div>
                      <div className="flex gap-1 mt-1.5">
                        {p.alergias && (
                          <Badge variant="destructive" className="text-[10px]">
                            Alergias
                          </Badge>
                        )}
                        {p.tipo_sangre && (
                          <Badge variant="outline" className="text-[10px]">
                            {p.tipo_sangre}
                          </Badge>
                        )}
                      </div>
                    </div>
                  </div>
                  <ArrowRight className="h-4 w-4 text-muted-foreground mt-2" />
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  )
}
