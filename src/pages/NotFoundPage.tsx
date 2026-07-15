import { useNavigate, useLocation } from 'react-router-dom'
import { SearchX, ArrowLeft, Home } from 'lucide-react'
import { Button } from '@/components/ui/button'

export default function NotFoundPage() {
  const navigate = useNavigate()
  const location = useLocation()

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center px-6 text-center">
      <SearchX className="h-16 w-16 text-[#1E5C8E] mb-4" />
      <h1 className="text-2xl font-bold text-[#1a2a3a] mb-2">Página no encontrada</h1>
      <p className="text-sm text-muted-foreground mb-1 max-w-md">
        La dirección que intentaste abrir no existe o fue movida.
      </p>
      <p className="text-xs text-gray-400 mb-6 break-all">{location.pathname}</p>
      <div className="flex flex-col sm:flex-row gap-3 w-full sm:w-auto">
        <Button variant="outline" onClick={() => navigate(-1)} className="w-full sm:w-auto">
          <ArrowLeft className="h-4 w-4 mr-2" /> Volver atrás
        </Button>
        <Button onClick={() => navigate('/')} className="w-full sm:w-auto bg-[#1E5C8E] hover:bg-[#164a70]">
          <Home className="h-4 w-4 mr-2" /> Ir al inicio
        </Button>
      </div>
    </div>
  )
}
