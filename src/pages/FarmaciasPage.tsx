import { useState, useMemo } from 'react'
import { medicamentosSeed } from '@/data/medicamentos-seed'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Pill, Search, X } from 'lucide-react'

const categorias = [
  { nombre: 'Analgesicos', color: 'bg-red-100 text-red-700 hover:bg-red-200' },
  { nombre: 'Antibioticos', color: 'bg-blue-100 text-blue-700 hover:bg-blue-200' },
  { nombre: 'Antiinflamatorios', color: 'bg-green-100 text-green-700 hover:bg-green-200' },
  { nombre: 'Antihistaminicos', color: 'bg-yellow-100 text-yellow-700 hover:bg-yellow-200' },
  { nombre: 'Vitaminas', color: 'bg-purple-100 text-purple-700 hover:bg-purple-200' },
  { nombre: 'Gastrointestinales', color: 'bg-orange-100 text-orange-700 hover:bg-orange-200' },
]

export default function FarmaciasPage() {
  const [search, setSearch] = useState('')
  const [categoriaActiva, setCategoriaActiva] = useState<string | null>(null)

  const medicamentosFiltrados = useMemo(() => {
    return medicamentosSeed.filter(med => {
      const matchSearch = search === '' || 
        med.nombre_generico.toLowerCase().includes(search.toLowerCase()) ||
        (med.nombre_comercial && med.nombre_comercial.toLowerCase().includes(search.toLowerCase()))
      
      const matchCategoria = !categoriaActiva || med.categoria === categoriaActiva
      
      return matchSearch && matchCategoria
    })
  }, [search, categoriaActiva])

  const handleCategoriaClick = (cat: string) => {
    if (categoriaActiva === cat) {
      setCategoriaActiva(null) // Deseleccionar si ya está activa
    } else {
      setCategoriaActiva(cat)
    }
  }

  const clearFilters = () => {
    setSearch('')
    setCategoriaActiva(null)
  }

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
        {(search || categoriaActiva) && (
          <button 
            onClick={clearFilters}
            className="absolute right-4 top-1/2 -translate-y-1/2 text-[#8a9aaa] hover:text-[#1E5C8E]"
          >
            <X className="h-5 w-5" />
          </button>
        )}
      </div>

      <div className="flex flex-wrap gap-2">
        {categorias.map(cat => (
          <button 
            key={cat.nombre} 
            onClick={() => handleCategoriaClick(cat.nombre)} 
            className={`px-4 py-2 rounded-full text-sm font-medium transition-all ${cat.color} ${
              categoriaActiva === cat.nombre ? 'ring-2 ring-offset-2 ring-[#1E5C8E] font-bold' : ''
            }`}
          >
            {cat.nombre}
          </button>
        ))}
      </div>

      {categoriaActiva && (
        <p className="text-sm text-[#8a9aaa]">
          Mostrando {medicamentosFiltrados.length} medicamento(s) en <span className="font-medium text-[#1E5C8E]">{categoriaActiva}</span>
        </p>
      )}

      {medicamentosFiltrados.length === 0 ? (
        <div className="text-center py-12 text-[#8a9aaa]">
          <Pill className="h-12 w-12 mx-auto mb-3 opacity-50" />
          <p>No se encontraron medicamentos</p>
          {(search || categoriaActiva) && (
            <button onClick={clearFilters} className="mt-2 text-[#1E5C8E] hover:underline text-sm">
              Limpiar filtros
            </button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {medicamentosFiltrados.map(med => (
            <Card key={med.nombre_generico} className="hover:shadow-lg transition-shadow">
              <CardHeader className="pb-2">
                <div className="flex justify-between items-start">
                  <div>
                    <CardTitle className="text-base">{med.nombre_generico}</CardTitle>
                    {med.nombre_comercial && <p className="text-sm text-[#8a9aaa]">{med.nombre_comercial}</p>}
                  </div>
                  {med.categoria && (
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                      categorias.find(c => c.nombre === med.categoria)?.color || 'bg-gray-100 text-gray-700'
                    }`}>
                      {med.categoria}
                    </span>
                  )}
                </div>
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="flex flex-wrap gap-1">
                  {med.presentacion && <span className="px-2 py-1 bg-[#e8f0f8] rounded text-xs text-[#1E5C8E]">{med.presentacion}</span>}
                  {med.concentracion && <span className="px-2 py-1 bg-[#e8f0f8] rounded text-xs text-[#1E5C8E]">{med.concentracion}</span>}
                </div>
                <div className="text-xs text-[#8a9aaa] space-y-1">
                  {med.via_administracion && <p>Via: {med.via_administracion}</p>}
                  {med.precio_referencia && <p className="font-medium text-[#1E5C8E]">Q{med.precio_referencia.toFixed(2)}</p>}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}