// src/pages/DispensarRecetaPage.tsx
// Dispensar Receta — verifica/despacha por TOKEN fuerte vía RPC (auth.uid + permiso
// recetas_dispensar + aislamiento por farmacia, POR ÍTEM). EzPayConnect.

import { useState, useEffect } from 'react'
import { useSearchParams, useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import {
  ArrowLeft,
  QrCode,
  Search,
  CheckCircle,
  AlertCircle,
  Package,
  Loader2,
  MapPin,
} from 'lucide-react'
import { Button } from '@/components/ui/button'

interface ItemDespacho {
  item_id: number
  nombre_medicamento: string
  dosis: string
  frecuencia: string
  cantidad: number
  instrucciones?: string
  dispensado: boolean
}

interface RecetaVerificada {
  receta_id: number
  dispatch_token: string
  estado_dispensacion: string
  paciente_nombre: string
  items: ItemDespacho[]
}

export default function DispensarRecetaPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()

  // Lee token desde URL (?codigo=XXX) o input manual
  const codigoFromURL = searchParams.get('codigo') || ''

  const [codigoQR, setCodigoQR] = useState(codigoFromURL)
  const [verificando, setVerificando] = useState(false)
  const [recetaData, setRecetaData] = useState<RecetaVerificada | null>(null)
  const [error, setError] = useState('')
  const [dispensando, setDispensando] = useState(false)
  const [farmaceuticoNombre, setFarmaceuticoNombre] = useState('')
  const [seleccionados, setSeleccionados] = useState<ItemDespacho[]>([])

  // Auto-verificar si viene token en URL
  useEffect(() => {
    if (codigoFromURL && !recetaData && !verificando) {
      verificarQR(codigoFromURL)
    }
  }, [codigoFromURL])

  const pendientes = recetaData?.items.filter((i) => !i.dispensado) ?? []
  const yaDispensada = !!recetaData && pendientes.length === 0

  const verificarQR = async (codigo?: string) => {
    const token = codigo || codigoQR.trim()
    if (!token) {
      setError('Ingresa el código de la receta')
      return
    }
    setVerificando(true)
    setError('')
    setRecetaData(null)

    // El RPC valida: token no expirado + rol con permiso recetas_dispensar + farmacia
    // del/los ítem(s) ∈ mi empresa. Devuelve SOLO los ítems de la farmacia del actor.
    const { data, error: rpcError } = await supabase.rpc('verificar_receta_despacho', {
      p_token: token,
    })

    if (rpcError) {
      setError(rpcError.message || 'Receta no válida o no autorizada')
      setVerificando(false)
      return
    }

    const rec = data as RecetaVerificada
    setRecetaData(rec)
    setSeleccionados((rec.items || []).filter((i) => !i.dispensado))
    setVerificando(false)
  }

  const dispensarReceta = async () => {
    if (!recetaData || !farmaceuticoNombre.trim()) {
      alert('Ingresa el nombre del farmacéutico')
      return
    }
    const itemIds = seleccionados.map((m) => m.item_id)
    if (itemIds.length === 0) {
      alert('No hay ítems pendientes para despachar')
      return
    }

    setDispensando(true)
    const { data, error: rpcError } = await supabase.rpc('registrar_dispensacion', {
      p_token: codigoQR || recetaData.dispatch_token,
      p_item_ids: itemIds,
      p_farmaceutico: farmaceuticoNombre.trim(),
    })
    setDispensando(false)

    if (rpcError) {
      alert('❌ ' + (rpcError.message || 'No se pudo despachar'))
      return
    }
    alert(`✅ Despachado: ${data?.despachados ?? 0} ítem(s)`)
    setRecetaData(null)
    setCodigoQR('')
    setSeleccionados([])
  }

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="flex items-center gap-3 mb-6">
        <Button variant="outline" size="sm" onClick={() => navigate('/dashboard')}
          className="border-[#1E5C8E] text-[#1E5C8E] hover:bg-[#e8f0f8]">
          <MapPin className="h-4 w-4 mr-2" />
          Dashboard
        </Button>
        <Button variant="outline" size="sm" onClick={() => navigate('/farmacias')}
          className="border-gray-300 text-gray-600 hover:bg-gray-100">
          <ArrowLeft className="h-4 w-4 mr-2" />
          Farmacias
        </Button>
      </div>

      <div className="flex items-center gap-4 mb-8">
        <div className="p-3 bg-white rounded-lg shadow-sm">
          <QrCode size={32} className="text-[#1E5C8E]" />
        </div>
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a]">Dispensar Receta</h1>
          <p className="text-gray-500">Escanea el código QR de la receta para verificar y dispensar</p>
        </div>
      </div>

      {/* Input token */}
      <div className="bg-white rounded-xl shadow-sm p-6 mb-6">
        <div className="flex gap-4">
          <div className="flex-1">
            <label className="text-sm text-gray-500 mb-2 block">Código de la Receta</label>
            <div className="flex gap-2">
              <input
                type="text"
                value={codigoQR}
                onChange={(e) => setCodigoQR(e.target.value)}
                placeholder="Pega o escanea el código de la receta"
                className="flex-1 p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E] font-mono"
              />
              <button
                onClick={() => verificarQR()}
                disabled={verificando}
                className="px-6 py-3 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold flex items-center gap-2 transition-colors disabled:opacity-50"
              >
                {verificando ? <Loader2 size={18} className="animate-spin" /> : <Search size={18} />}
                {verificando ? 'Verificando...' : 'Verificar'}
              </button>
            </div>
          </div>
        </div>

        {error && (
          <div className="mt-4 bg-red-50 border border-red-200 rounded-lg p-4 flex items-center gap-3">
            <AlertCircle size={20} className="text-red-500" />
            <span className="text-red-700">{error}</span>
          </div>
        )}
      </div>

      {/* Resultado verificación */}
      {recetaData && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className={`p-6 border-b ${yaDispensada ? 'bg-red-50 border-red-100' : 'bg-green-50 border-green-100'}`}>
            <div className="flex items-center gap-3">
              {yaDispensada ? (
                <AlertCircle size={24} className="text-red-500" />
              ) : (
                <CheckCircle size={24} className="text-green-500" />
              )}
              <div>
                <h2 className={`font-semibold ${yaDispensada ? 'text-red-700' : 'text-green-700'}`}>
                  {yaDispensada ? 'Receta ya dispensada (tus ítems)' : 'Receta válida'}
                </h2>
                <p className="text-sm text-gray-600">
                  {yaDispensada ? 'Todos los ítems asignados a tu farmacia ya fueron despachados.' : 'Lista para dispensar.'}
                </p>
              </div>
            </div>
          </div>

          {/* Datos receta (PHI mínima) */}
          <div className="p-6 border-b border-gray-100">
            <h3 className="font-semibold text-[#1a2a3a] mb-4">Datos de la Receta</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="bg-gray-50 p-4 rounded-lg">
                <label className="text-sm text-gray-500">Paciente</label>
                <p className="font-medium">{recetaData.paciente_nombre || 'N/A'}</p>
              </div>
              <div className="bg-gray-50 p-4 rounded-lg">
                <label className="text-sm text-gray-500">Estado</label>
                <p className="font-medium capitalize">{recetaData.estado_dispensacion}</p>
              </div>
            </div>
          </div>

          {/* Formulario de dispensación (ítems pendientes de TU farmacia) */}
          {!yaDispensada && (
            <div className="p-6">
              <h3 className="font-semibold text-[#1a2a3a] mb-4">Formulario de Dispensación</h3>

              <div className="mb-6">
                <label className="text-sm text-gray-500 mb-2 block">Nombre del Farmacéutico</label>
                <input
                  type="text"
                  value={farmaceuticoNombre}
                  onChange={(e) => setFarmaceuticoNombre(e.target.value)}
                  placeholder="Tu nombre"
                  className="w-full md:w-1/2 p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>

              <h4 className="font-medium text-[#1a2a3a] mb-3">Medicamentos a dispensar (tu farmacia)</h4>
              <div className="space-y-3 mb-6">
                {seleccionados.map((med) => (
                  <div key={med.item_id} className="flex items-center gap-4 bg-gray-50 p-4 rounded-lg">
                    <Package size={20} className="text-[#1E5C8E]" />
                    <div className="flex-1">
                      <p className="font-medium">{med.nombre_medicamento}</p>
                      <p className="text-sm text-gray-500">
                        {med.dosis} · {med.frecuencia} · cantidad: {med.cantidad}
                        {med.instrucciones ? ` · ${med.instrucciones}` : ''}
                      </p>
                    </div>
                  </div>
                ))}
              </div>

              <button
                onClick={dispensarReceta}
                disabled={dispensando || !farmaceuticoNombre.trim() || seleccionados.length === 0}
                className="w-full py-4 bg-green-600 hover:bg-green-700 text-white rounded-lg font-semibold text-lg flex items-center justify-center gap-2 transition-colors disabled:opacity-50"
              >
                {dispensando ? <Loader2 size={24} className="animate-spin" /> : <CheckCircle size={24} />}
                {dispensando ? 'Procesando...' : 'Confirmar Dispensación'}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
