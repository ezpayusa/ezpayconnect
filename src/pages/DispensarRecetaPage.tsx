// src/pages/DispensarRecetaPage.tsx
// RETIRADO (Frente B, sub-tarea #2): el despacho médico-side por QR/URL se retiró.
// El despacho ahora vive en el portal de farmacia (/farmacia/recetas: bandeja dirigida
// + walk-in con token fuerte). Esta página queda como AVISO 100% ESTÁTICO para enlaces
// viejos que traían el código en la query string: ya NO se lee ese parámetro, NO se
// llama ningún RPC y NO se maneja token — así se cierra el leak del token en la URL.
import { useNavigate } from 'react-router-dom'
import { Info, ArrowLeft } from 'lucide-react'
import { Button } from '@/components/ui/button'

export default function DispensarRecetaPage() {
  const navigate = useNavigate()
  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-8">
      <div className="max-w-md w-full bg-white rounded-xl shadow-sm border p-8 text-center">
        <div className="mx-auto w-12 h-12 rounded-full bg-[#e8f0f8] flex items-center justify-center mb-4">
          <Info className="h-6 w-6 text-[#1E5C8E]" />
        </div>
        <h1 className="text-xl font-bold text-[#1a2a3a] mb-2">El despacho se trasladó al portal de farmacia</h1>
        <p className="text-sm text-gray-600 mb-6">
          La verificación y dispensación de recetas ahora se hace desde el portal de la farmacia
          (bandeja de recetas entrantes y escaneo de QR), con acceso del personal de farmacia.
          Este enlace ya no procesa códigos.
        </p>
        <Button variant="outline" onClick={() => navigate('/dashboard')} className="gap-2">
          <ArrowLeft className="h-4 w-4" /> Volver al inicio
        </Button>
      </div>
    </div>
  )
}
