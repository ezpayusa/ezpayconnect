import { useAuth } from '@/hooks/useAuth'

// PLACEHOLDER de la tanda 1. La lista real (y la ficha) son la tanda 2.
//
// No hace NINGUNA query: la ruta existe para poder verificar el ruteo y el guard en el navegador
// sin que un bug de datos se confunda con un bug de acceso. Esa separación es la razón de que los
// cimientos vayan en una tanda propia.
export default function ProspectosPage() {
  const { perfil } = useAuth()
  const esSupervisor = perfil?.rol === 'supervisor_comercial'

  return (
    <div className="rounded-lg border border-dashed border-gray-300 bg-white p-6">
      <h1 className="text-lg font-semibold text-gray-900">Prospectos</h1>
      <p className="mt-1 text-sm text-gray-600">
        {esSupervisor
          ? 'Acá va la cartera de tu equipo.'
          : 'Acá va tu cartera de prospectos.'}
      </p>
      <p className="mt-4 inline-block rounded bg-amber-50 px-3 py-1.5 text-xs font-medium text-amber-800">
        En obra — pantalla de la tanda 2
      </p>
      <p className="mt-4 text-xs text-gray-500">
        Sesión: <span className="font-mono">{perfil?.nombre_completo || perfil?.rol || '—'}</span>
        {' · '}rol <span className="font-mono">{perfil?.rol}</span>
      </p>
    </div>
  )
}
