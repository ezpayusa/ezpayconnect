import { useState, useEffect } from 'react'
import { useMedicamentos } from '@/hooks/useRecetas'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Pill, Search, Loader2 } from 'lucide-react'

export default function FarmaciasPage() {
  const { medicamentos, fetchMedicamentos } = useMedicamentos()
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    setLoading(true)
    fetchMedicamentos(search).finally(() => setLoading(false))
  }, [search])

  const categorias = [
    { nombre: 'Analgesicos', color: 'bg-red-100 text-red-700' },
    { nombre: 'Antibioticos', color: 'bg-blue-100 text-blue-700' },
    { nombre: 'Antiinflamatorios', color: 'bg-green-100 text-green-700' },
    { nombre: 'Antihistaminicos', color: 'bg-yellow-100 text-yellow-700' },
    { nombre: 'Vitaminas', color: 'bg-purple-100 text-purple-700' },
    { nombre: 'Gastrointestinales', color: 'bg-orange-100 text-orange-700' },
  ]

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-3xl font-bold text-[#1a2a3a]">Buscador de Medicamentos</h1>
        <p className="text-[#8a9aaa] mt-1">Busca medicamentos por nombre o categoria</p>
      </div>

      <div className="relative">
        <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-[#8a9aaa]" />
        <Input
          placeholder="Buscar medicamento por nombre generico o comercial..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="pl-12 h-14 text-lg"
        />
      </div>

      <div className="flex flex-wrap gap-2">
        {categorias.map(cat => (
          <button key={cat.nombre} onClick={() => setSearch(cat.nombre)} className={`px-4 py-2 rounded-full text-sm font-medium transition-all hover:opacity-80 ${cat.color}`}>
            {cat.nombre}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" /></div>
      ) : medicamentos.length === 0 ? (
        <div className="text-center py-12 text-[#8a9aaa]">
          <Pill className="h-12 w-12 mx-auto mb-3 opacity-50" />
          <p>{search ? 'No se encontraron medicamentos' : 'Escribe para buscar medicamentos'}</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {medicamentos.map(med => (
            <Card key={med.id} className="hover:shadow-lg transition-shadow">
              <CardHeader className="pb-2">
                <CardTitle className="text-base">{med.nombre_generico}</CardTitle>
                {med.nombre_comercial && <p className="text-sm text-[#8a9aaa]">{med.nombre_comercial}</p>}
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="flex flex-wrap gap-1">
                  {med.presentacion && <span className="px-2 py-1 bg-[#e8f0f8] rounded text-xs text-[#1E5C8E]">{med.presentacion}</span>}
                  {med.concentracion && <span className="px-2 py-1 bg-[#e8f0f8] rounded text-xs text-[#1E5C8E]">{med.concentracion}</span>}
                </div>
                <div className="text-xs text-[#8a9aaa] space-y-1">
                  {med.laboratorio && <p>Laboratorio: {med.laboratorio}</p>}
                  {med.via_administracion && <p>Via: {med.via_administracion}</p>}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
