import type { FiltroCitaEstado } from '@/medico/types/medico.types'

interface CitasFilterProps {
  filtro: FiltroCitaEstado
  onChange: (f: FiltroCitaEstado) => void
  counts: Record<string, number>
}

const filtros: { key: FiltroCitaEstado; label: string }[] = [
  { key: 'todos', label: 'Todas' },
  { key: 'solicitada', label: 'Solicitadas' },
  { key: 'agendada', label: 'Agendadas' },
  { key: 'confirmada', label: 'Confirmadas' },
  { key: 'en_espera', label: 'En espera' },
  { key: 'en_curso', label: 'En curso' },
  { key: 'completada', label: 'Completadas' },
  { key: 'cancelada', label: 'Canceladas' },
]

export default function CitasFilter({ filtro, onChange, counts }: CitasFilterProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {filtros.map((f) => {
        const active = filtro === f.key
        const count = counts[f.key] || 0
        return (
          <button
            key={f.key}
            onClick={() => onChange(f.key)}
            className={`px-3 py-1.5 rounded-full text-sm font-medium transition-all ${
              active
                ? 'bg-[#1E5C8E] text-white shadow-sm'
                : 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
            }`}
          >
            {f.label}
            {count > 0 && (
              <span className={`ml-1.5 text-xs px-1.5 py-0.5 rounded-full ${
                active ? 'bg-white/20 text-white' : 'bg-gray-100 text-gray-600'
              }`}>
                {count}
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}
