// src/pages/DispensarRecetaPage.tsx
// Dia 18: Dispensar Receta - Escanear QR y dispensar
// EzPayConnect

import { useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/hooks/useAuth'
import {
  ArrowLeft,
  QrCode,
  Search,
  CheckCircle,
  AlertCircle,
  Package,
  X,
  Loader2,
  Pill
} from 'lucide-react'
import { useNavigate } from 'react-router-dom'

const EDGE_FUNCTION_URL = 'https://fqnsmvkxsuujahhmpzuk.supabase.co/functions/v1'

interface RecetaVerificada {
  receta: any
  estado: string
  medicamentos_disponibles: any[]
  dispensacion?: any
}

export default function DispensarRecetaPage() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const [codigoQR, setCodigoQR] = useState('')
  const [verificando, setVerificando] = useState(false)
  const [recetaData, setRecetaData] = useState<RecetaVerificada | null>(null)
  const [error, setError] = useState('')
  const [dispensando, setDispensando] = useState(false)
  const [farmaciaId, setFarmaciaId] = useState('')
  const [farmaceuticoNombre, setFarmaceuticoNombre] = useState('')
  const [medicamentosSeleccionados, setMedicamentosSeleccionados] = useState<any[]>([])

  const verificarQR = async () => {
    if (!codigoQR.trim()) {
      setError('Ingresa un codigo QR')
      return
    }

    setVerificando(true)
    setError('')
    setRecetaData(null)

    try {
      const { data: result, error: fnError } = await supabase.functions.invoke('verificar-receta-qr', {
        body: { codigo_qr: codigoQR.trim() }
      })

      if (fnError) throw fnError

      if (result?.success) {
        setRecetaData(result.data)
        if (result.data.estado === 'pendiente') {
          setMedicamentosSeleccionados(
            result.data.medicamentos_disponibles.map((m: any) => ({
              nombre: m.nombre_medicamento,
              cantidad: 1,
              precio: m.precio_unitario || 0,
              farmacia_id: m.farmacia_id
            }))
          )
        }
      } else {
        setError(result?.error || 'Error al verificar')
      }
    } catch (err: any) {
      setError(err.message || 'Error de conexion')
    } finally {
      setVerificando(false)
    }
  }

  const dispensarReceta = async () => {
    if (!recetaData?.receta || !farmaciaId || !farmaceuticoNombre) {
      alert('Completa todos los campos requeridos')
      return
    }

    setDispensando(true)

    try {
      const total = medicamentosSeleccionados.reduce((sum, m) => sum + (m.precio * m.cantidad), 0)

      const { data: result, error: fnError } = await supabase.functions.invoke('registrar-dispensacion', {
        body: {
          receta_avanzada_id: recetaData.receta.id,
          farmacia_id: parseInt(farmaciaId),
          paciente_id: recetaData.receta.paciente_id,
          medico_id: recetaData.receta.medico_id,
          codigo_qr: codigoQR,
          medicamentos_dispensados: medicamentosSeleccionados,
          total_dispensado: total,
          estado_dispensacion: 'completada',
          farmaceutico_nombre: farmaceuticoNombre
        }
      })

      if (fnError) throw fnError

      if (result?.success) {
        alert('✅ Receta dispensada exitosamente')
        setRecetaData(null)
        setCodigoQR('')
        setMedicamentosSeleccionados([])
      } else {
        alert('❌ Error: ' + result?.error)
      }
    } catch (err: any) {
      alert('❌ Error: ' + err.message)
    } finally {
      setDispensando(false)
    }
  }

  const actualizarCantidad = (index: number, cantidad: number) => {
    const updated = [...medicamentosSeleccionados]
    updated[index].cantidad = Math.max(1, cantidad)
    setMedicamentosSeleccionados(updated)
  }

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="flex items-center gap-4 mb-8">
        <button 
          onClick={() => navigate('/farmacias')}
          className="p-2 bg-white rounded-lg hover:bg-gray-100 transition-colors shadow-sm"
        >
          <ArrowLeft size={24} className="text-[#1E5C8E]" />
        </button>
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a] flex items-center gap-3">
            <QrCode size={32} className="text-[#1E5C8E]" />
            Dispensar Receta
          </h1>
          <p className="text-gray-500">Escanea el codigo QR de la receta para verificar y dispensar</p>
        </div>
      </div>

      {/* Input QR */}
      <div className="bg-white rounded-xl shadow-sm p-6 mb-6">
        <div className="flex gap-4">
          <div className="flex-1">
            <label className="text-sm text-gray-500 mb-2 block">Codigo QR de la Receta</label>
            <div className="flex gap-2">
              <input
                type="text"
                value={codigoQR}
                onChange={(e) => setCodigoQR(e.target.value)}
                placeholder="Ej: EZP-1234567890-ABC123"
                className="flex-1 p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E] font-mono"
              />
              <button
                onClick={verificarQR}
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

      {/* Resultado verificacion */}
      {recetaData && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          {/* Estado */}
          <div className={`p-6 border-b ${
            recetaData.estado === 'ya_dispensada' ? 'bg-red-50 border-red-100' : 'bg-green-50 border-green-100'
          }`}>
            <div className="flex items-center gap-3">
              {recetaData.estado === 'ya_dispensada' ? (
                <AlertCircle size={24} className="text-red-500" />
              ) : (
                <CheckCircle size={24} className="text-green-500" />
              )}
              <div>
                <h2 className={`font-semibold ${
                  recetaData.estado === 'ya_dispensada' ? 'text-red-700' : 'text-green-700'
                }`}>
                  {recetaData.estado === 'ya_dispensada' ? 'Receta ya dispensada' : 'Receta valida'}
                </h2>
                <p className="text-sm text-gray-600">{recetaData.mensaje}</p>
              </div>
            </div>
          </div>

          {/* Datos receta */}
          <div className="p-6 border-b border-gray-100">
            <h3 className="font-semibold text-[#1a2a3a] mb-4">Datos de la Receta</h3>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="bg-gray-50 p-4 rounded-lg">
                <label className="text-sm text-gray-500">Paciente</label>
                <p className="font-medium">{recetaData.receta.paciente?.nombre || 'N/A'}</p>
              </div>
              <div className="bg-gray-50 p-4 rounded-lg">
                <label className="text-sm text-gray-500">Medico</label>
                <p className="font-medium">{recetaData.receta.medico?.nombre || 'N/A'}</p>
              </div>
              <div className="bg-gray-50 p-4 rounded-lg">
                <label className="text-sm text-gray-500">Codigo QR</label>
                <p className="font-mono text-sm">{recetaData.receta.codigo_qr}</p>
              </div>
            </div>
          </div>

          {/* Si ya fue dispensada, mostrar detalles */}
          {recetaData.estado === 'ya_dispensada' && recetaData.dispensacion && (
            <div className="p-6">
              <h3 className="font-semibold text-[#1a2a3a] mb-4">Detalles de la dispensacion</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-gray-50 p-4 rounded-lg">
                  <label className="text-sm text-gray-500">Farmacia</label>
                  <p className="font-medium">{recetaData.dispensacion.farmacia?.nombre || 'N/A'}</p>
                </div>
                <div className="bg-gray-50 p-4 rounded-lg">
                  <label className="text-sm text-gray-500">Fecha</label>
                  <p className="font-medium">{new Date(recetaData.dispensacion.fecha_dispensacion).toLocaleString('es-ES')}</p>
                </div>
                <div className="bg-gray-50 p-4 rounded-lg">
                  <label className="text-sm text-gray-500">Farmaceutico</label>
                  <p className="font-medium">{recetaData.dispensacion.farmaceutico_nombre || 'N/A'}</p>
                </div>
              </div>
            </div>
          )}

          {/* Si esta pendiente, formulario de dispensacion */}
          {recetaData.estado === 'pendiente' && (
            <div className="p-6">
              <h3 className="font-semibold text-[#1a2a3a] mb-4">Formulario de Dispensacion</h3>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
                <div>
                  <label className="text-sm text-gray-500 mb-2 block">Farmacia</label>
                  <select
                    value={farmaciaId}
                    onChange={(e) => setFarmaciaId(e.target.value)}
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  >
                    <option value="">Seleccionar farmacia</option>
                    {recetaData.medicamentos_disponibles
                      .filter((m: any, i: number, arr: any[]) => arr.findIndex(t => t.farmacia_id === m.farmacia_id) === i)
                      .map((m: any) => (
                        <option key={m.farmacia_id} value={m.farmacia_id}>{m.farmacia?.nombre || `Farmacia ${m.farmacia_id}`}</option>
                      ))}
                  </select>
                </div>
                <div>
                  <label className="text-sm text-gray-500 mb-2 block">Nombre del Farmaceutico</label>
                  <input
                    type="text"
                    value={farmaceuticoNombre}
                    onChange={(e) => setFarmaceuticoNombre(e.target.value)}
                    placeholder="Tu nombre"
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
              </div>

              {/* Medicamentos */}
              <h4 className="font-medium text-[#1a2a3a] mb-3">Medicamentos a dispensar</h4>
              <div className="space-y-3 mb-6">
                {medicamentosSeleccionados.map((med, idx) => (
                  <div key={idx} className="flex items-center gap-4 bg-gray-50 p-4 rounded-lg">
                    <Package size={20} className="text-[#1E5C8E]" />
                    <div className="flex-1">
                      <p className="font-medium">{med.nombre}</p>
                      <p className="text-sm text-gray-500">Q{med.precio?.toFixed(2)} c/u</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <label className="text-sm text-gray-500">Cantidad:</label>
                      <input
                        type="number"
                        min="1"
                        value={med.cantidad}
                        onChange={(e) => actualizarCantidad(idx, parseInt(e.target.value))}
                        className="w-20 p-2 border border-gray-200 rounded-lg text-center"
                      />
                    </div>
                    <div className="text-right min-w-[100px]">
                      <p className="font-semibold">Q{(med.precio * med.cantidad).toFixed(2)}</p>
                    </div>
                  </div>
                ))}
              </div>

              {/* Total */}
              <div className="bg-[#1E5C8E]/10 p-4 rounded-lg mb-6">
                <div className="flex justify-between items-center">
                  <span className="font-semibold text-[#1a2a3a]">Total a pagar:</span>
                  <span className="text-2xl font-bold text-[#1E5C8E]">
                    Q{medicamentosSeleccionados.reduce((sum, m) => sum + (m.precio * m.cantidad), 0).toFixed(2)}
                  </span>
                </div>
              </div>

              <button
                onClick={dispensarReceta}
                disabled={dispensando || !farmaciaId || !farmaceuticoNombre}
                className="w-full py-4 bg-green-600 hover:bg-green-700 text-white rounded-lg font-semibold text-lg flex items-center justify-center gap-2 transition-colors disabled:opacity-50"
              >
                {dispensando ? <Loader2 size={24} className="animate-spin" /> : <CheckCircle size={24} />}
                {dispensando ? 'Procesando...' : 'Confirmar Dispensacion'}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
