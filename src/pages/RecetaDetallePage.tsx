import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { useRecetas } from '@/hooks/useRecetas'
import { generarPDFReceta, imprimirPDFReceta } from '@/lib/pdfReceta'
import EnviarRecetaEmail from '@/components/recetas/EnviarRecetaEmail'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { Skeleton } from '@/components/ui/skeleton'
import { toast } from 'sonner'
import {
  ArrowLeft,
  Printer,
  Download,
  Mail,
  QrCode,
  Pill,
  Clock,
  Calendar,
  User,
  Stethoscope,
  MapPin,
  Phone,
  MapPin,
  AlertTriangle
} from 'lucide-react'

import { QRCodeSVG } from 'qrcode.react'

export default function RecetaDetallePage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { user, perfil } = useAuth()
  const { getRecetaCompleta } = useRecetas()

  const [receta, setReceta] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [showQR, setShowQR] = useState(false)
  const [showEmailModal, setShowEmailModal] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const recetaId = parseInt(id || '0', 10)
  const recetaCargadaRef = useRef<number | null>(null)

  useEffect(() => {
    if (!recetaId || isNaN(recetaId)) {
      setError('ID de receta inválido')
      setLoading(false)
      return
    }

    // Evitar llamadas repetidas a getRecetaCompleta para el mismo ID
    if (recetaCargadaRef.current === recetaId) return

    const cargarReceta = async () => {
      try {
        setLoading(true)
        setError(null)
        console.log('[RecetaDetalle] Cargando receta ID:', recetaId)

        const data = await getRecetaCompleta(recetaId)
        console.log('[RecetaDetalle] Respuesta:', data)

        if (data?.receta) {
          // Normalizar estructura: el render espera receta plana con items, paciente
          setReceta({
            ...data.receta,
            items: data.items || [],
            paciente: data.paciente
          })
        } else {
          setError(`No se encontró la receta con ID ${recetaId}. Es posible que no exista o que no tenga permisos para verla.`)
        }
        recetaCargadaRef.current = recetaId
      } catch (err: any) {
        console.error('[RecetaDetalle] Error:', err)
        setError(err?.message || 'Error al cargar la receta')
        recetaCargadaRef.current = recetaId
      } finally {
        setLoading(false)
      }
    }

    cargarReceta()
  }, [recetaId, getRecetaCompleta])

  // === QR URL para dispensar receta en farmacia ===
  const getQRUrl = () => {
    if (!receta) return ''
    const codigo = receta.codigo_qr || `EZP-${receta.id}`
    return `https://med.ezpayconnect.com/dispensar-receta?codigo=${codigo}`
  }

  // === HANDLERS ===
  const handleDescargarPDF = () => {
    const medico = receta.medico || perfil
    if (!receta?.paciente || !medico || !receta?.items) {
      toast.error('Faltan datos para generar el PDF')
      return
    }
    generarPDFReceta(receta, receta.items, receta.paciente, medico)
    toast.success('PDF descargado')
  }

  const handleImprimir = () => {
    const medico = receta.medico || perfil
    if (!receta?.paciente || !medico || !receta?.items) {
      toast.error('Faltan datos para imprimir')
      return
    }
    imprimirPDFReceta(receta, receta.items, receta.paciente, medico)
    toast.success('Abriendo ventana de impresión')
  }

  const handleEnviarEmail = () => {
    setShowEmailModal(true)
  }

  // === RENDER ERROR ===
  if (error) {
    return (
      <div className="min-h-screen bg-gray-50 p-6">
        <div className="max-w-2xl mx-auto">
          <Button variant="outline" onClick={() => navigate('/recetas')} className="mb-6 gap-2">
            <ArrowLeft className="h-4 w-4" />
            Volver a Recetas
          </Button>
          <Card className="border-red-200 bg-red-50">
            <CardContent className="p-6 text-center space-y-4">
              <AlertTriangle className="h-12 w-12 text-red-500 mx-auto" />
              <h2 className="text-xl font-semibold text-red-700">Error al cargar la receta</h2>
              <p className="text-red-600">{error}</p>
              <div className="text-sm text-gray-500 bg-white rounded p-3">
                <p className="font-mono">Receta ID: {recetaId}</p>
                <p>Usuario: {user?.email || 'No autenticado'}</p>
              </div>
              <Button onClick={() => window.location.reload()} variant="outline">
                Reintentar
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    )
  }

  // === RENDER LOADING ===
  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 p-6">
        <div className="max-w-4xl mx-auto space-y-4">
          <Skeleton className="h-8 w-48" />
          <Skeleton className="h-32 w-full" />
          <Skeleton className="h-64 w-full" />
        </div>
      </div>
    )
  }

  if (!receta) return null

  const fecha = new Date(receta.created_at).toLocaleDateString('es-GT', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  })

  const tieneFarmaciaAsignada = receta.items?.some((item: any) => item.farmacia || item.farmacia_id)

  return (
    <div className="min-h-screen bg-gray-50 p-4 md:p-6">
      <div className="max-w-4xl mx-auto space-y-6">

        {/* === HEADER === */}
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div className="flex items-center gap-3">
            <Button variant="outline" size="icon" onClick={() => navigate('/recetas')}>
              <ArrowLeft className="h-4 w-4" />
            </Button>
            <div>
              <h1 className="text-2xl font-bold text-[#1a2a3a]">Receta Médica</h1>
              <p className="text-sm text-gray-500">Folio: REC-{String(receta.id).padStart(6, '0')}</p>
            </div>
          </div>

          <div className="flex flex-wrap gap-2">
            <Button variant="outline" onClick={handleImprimir} className="gap-2">
              <Printer className="h-4 w-4" />
              Imprimir
            </Button>
            <Button variant="outline" onClick={handleDescargarPDF} className="gap-2">
              <Download className="h-4 w-4" />
              PDF
            </Button>
            <Button variant="outline" onClick={handleEnviarEmail} className="gap-2">
              <Mail className="h-4 w-4" />
              Email
            </Button>
            <Button
              variant={showQR ? 'default' : 'outline'}
              onClick={() => setShowQR(!showQR)}
              className="gap-2"
            >
              <QrCode className="h-4 w-4" />
              {showQR ? 'Ocultar QR' : 'Ver QR'}
            </Button>
          </div>
        </div>

        {/* === QR CODE === */}
        {showQR && (
          <Card className="border-dashed border-2 border-[#1E5C8E]">
            <CardContent className="p-6 flex flex-col items-center gap-4">
              <QRCodeSVG
                value={getQRUrl()}
                size={200}
                level="H"
                includeMargin={true}
              />
              <div className="text-center space-y-1">
                <p className="text-sm font-medium text-[#1a2a3a]">Escanea para ver en farmacia</p>
                <p className="text-xs text-gray-500 break-all max-w-sm">{getQRUrl()}</p>
                {tieneFarmaciaAsignada && (
                  <Badge variant="outline" className="mt-2 bg-green-50 text-green-700 border-green-200">
                    Farmacia asignada incluida en el QR
                  </Badge>
                )}
              </div>
            </CardContent>
          </Card>
        )}

        {/* === INFO GENERAL === */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Paciente */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-gray-500 flex items-center gap-2">
                <User className="h-4 w-4" />
                Paciente
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <p className="text-lg font-semibold text-[#1a2a3a]">
                {receta.paciente?.nombre} {receta.paciente?.apellido}
              </p>
              <div className="text-sm text-gray-600 space-y-1">
                <p className="flex items-center gap-2">
                  <Phone className="h-3.5 w-3.5" />
                  {receta.paciente?.telefono || 'Sin teléfono'}
                </p>
                <p className="flex items-center gap-2">
                  <Mail className="h-3.5 w-3.5" />
                  {receta.paciente?.email || 'Sin email'}
                </p>
                {receta.paciente?.fecha_nacimiento && (
                  <p className="flex items-center gap-2">
                    <Calendar className="h-3.5 w-3.5" />
                    {new Date(receta.paciente.fecha_nacimiento).toLocaleDateString('es-GT')}
                  </p>
                )}
                {receta.paciente?.alergias && (
                  <p className="flex items-center gap-2 text-amber-600">
                    <span className="font-medium">Alergias:</span> {receta.paciente.alergias}
                  </p>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Médico */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium text-gray-500 flex items-center gap-2">
                <Stethoscope className="h-4 w-4" />
                Médico
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <p className="text-lg font-semibold text-[#1a2a3a]">
                Dr. {receta.medico?.nombre_completo || perfil?.nombre_completo || 'Médico'}
              </p>
              <div className="text-sm text-gray-600 space-y-1">
                <p className="flex items-center gap-2">
                  <Mail className="h-3.5 w-3.5" />
                  {receta.medico?.email || perfil?.email || 'Sin email'}
                </p>
                <p className="flex items-center gap-2">
                  <Phone className="h-3.5 w-3.5" />
                  {receta.medico?.telefono || perfil?.telefono || 'Sin teléfono'}
                </p>
                <p className="flex items-center gap-2">
                  <Calendar className="h-3.5 w-3.5" />
                  {fecha}
                </p>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* === MEDICAMENTOS === */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Pill className="h-5 w-5 text-[#1E5C8E]" />
              Medicamentos Prescritos
              <Badge variant="secondary" className="ml-2">
                {receta.items?.length || 0}
              </Badge>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {receta.items?.map((item: any, idx: number) => (
              <div
                key={item.id || idx}
                className="border rounded-lg p-4 space-y-3 hover:bg-gray-50 transition-colors"
              >
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <span className="flex items-center justify-center w-8 h-8 rounded-full bg-[#1E5C8E] text-white text-sm font-bold">
                      {idx + 1}
                    </span>
                    <div>
                      <p className="font-semibold text-[#1a2a3a]">{item.nombre_medicamento}</p>
                      <p className="text-sm text-gray-500">{item.dosis} — {item.frecuencia}</p>
                    </div>
                  </div>
                  <Badge variant="outline">Cant: {item.cantidad}</Badge>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm pl-11">
                  <div className="flex items-center gap-2 text-gray-600">
                    <Clock className="h-3.5 w-3.5" />
                    <span>Duración: {item.duracion || 'Según indicación médica'}</span>
                  </div>
                  {item.instrucciones && (
                    <div className="flex items-start gap-2 text-gray-600 sm:col-span-2">
                      <span className="font-medium min-w-[90px]">Instrucciones:</span>
                      <span>{item.instrucciones}</span>
                    </div>
                  )}
                </div>

                {/* Farmacia asignada */}
                {(item.farmacia || item.farmacia_id) && (
                  <div className="pl-11">
                    <div className="bg-green-50 border border-green-200 rounded-lg p-3">
                      <div className="flex items-center gap-2 text-green-700 font-medium mb-1">
                        <MapPin className="h-4 w-4" />
                        Farmacia Asignada
                      </div>
                      <div className="text-sm text-green-800 space-y-0.5">
                        <p className="font-semibold">{item.farmacia?.nombre || 'Farmacia #' + item.farmacia_id}</p>
                        {item.farmacia?.direccion && (
                          <p className="flex items-center gap-1">
                            <MapPin className="h-3 w-3" />
                            {item.farmacia.direccion}
                          </p>
                        )}
                        {item.farmacia?.telefono && (
                          <p className="flex items-center gap-1">
                            <Phone className="h-3 w-3" />
                            {item.farmacia.telefono}
                          </p>
                        )}
                      </div>
                    </div>
                  </div>
                )}

                {idx < receta.items.length - 1 && <Separator className="mt-4" />}
              </div>
            ))}

            {(!receta.items || receta.items.length === 0) && (
              <p className="text-center text-gray-500 py-8">No hay medicamentos en esta receta</p>
            )}
          </CardContent>
        </Card>

        {/* === INSTRUCCIONES GENERALES === */}
        {receta.instrucciones_generales && (
          <Card>
            <CardHeader>
              <CardTitle>Instrucciones Generales</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-gray-700 whitespace-pre-wrap">{receta.instrucciones_generales}</p>
            </CardContent>
          </Card>
        )}

        {/* === FIRMA === */}
        <div className="text-center py-8 space-y-2">
          <div className="w-48 h-px bg-[#1E5C8E] mx-auto" />
          <p className="font-semibold text-[#1a2a3a]">Dr. {receta.medico?.nombre_completo || perfil?.nombre_completo || 'Médico'}</p>
          <p className="text-sm text-gray-500">Firma y Sello Médico</p>
          <p className="text-xs text-gray-400 mt-4">
            Documento generado digitalmente por EzPayConnect — {fecha}
          </p>
        </div>
      </div>

      {/* Modal de enviar receta por email */}
      <EnviarRecetaEmail
        open={showEmailModal}
        onOpenChange={setShowEmailModal}
        receta={receta}
        medicamentos={receta.items || []}
        medicoNombre={perfil?.nombre_completo}
      />
    </div>
  )
}