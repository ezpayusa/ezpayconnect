import { useState } from 'react'
import { useUbicacionesMedico } from '@/proveedor/hooks/useUbicacionesMedico'
import { useMedicosDisponibles } from '@/proveedor/hooks/useMedicosDisponibles'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { toast } from 'sonner'
import {
  MapPin, Search, CheckCircle, AlertTriangle, Edit3, Trash2,
  Navigation, Loader2, Stethoscope, Globe
} from 'lucide-react'
import MapaInteractivo from '@/components/MapaInteractivo'

export default function AdminUbicacionesMedicosPage() {
  const { ubicaciones, loading, saving, guardarUbicacion, eliminarUbicacion, geocodificar } = useUbicacionesMedico()
  const { medicos, loading: loadingMedicos, buscarMedicos } = useMedicosDisponibles()
  const { cuenta } = useProveedorAuth()
  const [query, setQuery] = useState('')
  const [editandoMedico, setEditandoMedico] = useState<string | null>(null)
  const [direccion, setDireccion] = useState('')
  const [lat, setLat] = useState('')
  const [lng, setLng] = useState('')
  const [notas, setNotas] = useState('')
  const [geocodificando, setGeocodificando] = useState(false)
  const [mostrarMapaManual, setMostrarMapaManual] = useState(false)
  const [urlGoogleMaps, setUrlGoogleMaps] = useState('')

  const esAdmin = cuenta?.rol_en_empresa === 'admin' || cuenta?.rol_en_empresa === 'editor'

  if (!esAdmin) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">Solo administradores pueden gestionar ubicaciones.</p>
      </div>
    )
  }

  const handleBuscar = (e: React.FormEvent) => {
    e.preventDefault()
    buscarMedicos(query)
  }

  const abrirEditar = (medicoId: string, nombre: string) => {
    const ubi = ubicaciones.find((u) => u.medico_id === medicoId)
    setEditandoMedico(medicoId)
    setDireccion(ubi?.direccion || '')
    setLat(ubi?.lat?.toString() || '')
    setLng(ubi?.lng?.toString() || '')
    setNotas(ubi?.notas || '')
    setMostrarMapaManual(false)
    setUrlGoogleMaps('')
  }

  const handleGeocodificar = async () => {
    if (!direccion.trim()) {
      toast.error('Escribe una dirección primero')
      return
    }
    setGeocodificando(true)
    const coords = await geocodificar(direccion)
    setGeocodificando(false)
    if (coords) {
      setLat(coords.lat.toString())
      setLng(coords.lng.toString())
      toast.success('Coordenadas obtenidas')
      setMostrarMapaManual(false)
    } else {
      toast.error('No se encontraron coordenadas automáticamente. Usa el mapa para ubicar manualmente.')
      setMostrarMapaManual(true)
    }
  }

  const extraerCoordenadasDeUrl = () => {
    // Formatos soportados:
    // https://www.google.com/maps/@14.6349,-90.5069,15z
    // https://www.google.com/maps/place/.../@14.6349,-90.5069,...
    // https://maps.app.goo.gl/... (short URLs no soportados)
    const regex = /@(-?\d+\.\d+),(-?\d+\.\d+)/
    const match = urlGoogleMaps.match(regex)
    if (match) {
      setLat(match[1])
      setLng(match[2])
      toast.success('Coordenadas extraídas de la URL')
    } else {
      toast.error('No se pudieron extraer coordenadas de esa URL. Asegúrate de que sea un enlace de Google Maps con @lat,lng')
    }
  }

  const handleGuardar = async () => {
    const ok = await guardarUbicacion(editandoMedico!, {
      direccion,
      lat: lat ? parseFloat(lat) : null,
      lng: lng ? parseFloat(lng) : null,
      notas,
    })
    if (ok) setEditandoMedico(null)
  }

  const medicosConUbicacion = medicos.map((m) => {
    const ubi = ubicaciones.find((u) => u.medico_id === m.id)
    return { ...m, tieneUbicacion: !!ubi, ubicacion: ubi }
  })

  return (
    <div className="p-4 max-w-5xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <MapPin className="w-6 h-6" />
          Ubicaciones de Médicos
        </h1>
        <p className="text-muted-foreground">
          Gestiona las direcciones de consultorio para tus visitas. Estas ubicaciones son privadas de tu empresa.
        </p>
      </div>

      {/* Buscador */}
      <Card>
        <CardContent className="pt-6">
          <form onSubmit={handleBuscar} className="flex gap-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Buscar médico por nombre..."
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="pl-9"
              />
            </div>
            <Button type="submit" disabled={loadingMedicos}>
              {loadingMedicos ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4 mr-1" />}
              Buscar
            </Button>
          </form>
        </CardContent>
      </Card>

      {/* Lista de médicos */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {medicosConUbicacion.map((m) => (
          <Card key={m.id} className={m.tieneUbicacion ? 'border-green-200' : 'border-red-200'}>
            <CardContent className="p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center">
                    <Stethoscope className="h-5 w-5 text-primary" />
                  </div>
                  <div>
                    <h3 className="font-semibold">{m.nombre_completo}</h3>
                    <p className="text-sm text-muted-foreground">{m.email}</p>
                  </div>
                </div>
                {m.tieneUbicacion ? (
                  <Badge variant="outline" className="border-green-500 text-green-600">
                    <CheckCircle className="w-3 h-3 mr-1" /> Ubicado
                  </Badge>
                ) : (
                  <Badge variant="outline" className="border-red-500 text-red-600">
                    <AlertTriangle className="w-3 h-3 mr-1" /> Sin ubicación
                  </Badge>
                )}
              </div>

              {m.ubicacion?.direccion && (
                <div className="mt-3 text-sm bg-muted/50 rounded p-2 space-y-1">
                  <p className="flex items-center gap-2">
                    <MapPin className="w-4 h-4 text-muted-foreground" />
                    {m.ubicacion.direccion}
                  </p>
                  {m.ubicacion.lat && m.ubicacion.lng && (
                    <p className="flex items-center gap-2 text-muted-foreground">
                      <Navigation className="w-4 h-4" />
                      {m.ubicacion.lat.toFixed(5)}, {m.ubicacion.lng.toFixed(5)}
                    </p>
                  )}
                  {m.ubicacion.notas && (
                    <p className="text-xs italic">{m.ubicacion.notas}</p>
                  )}
                </div>
              )}

              <div className="flex gap-2 mt-3">
                <Button size="sm" variant="outline" onClick={() => abrirEditar(m.id, m.nombre_completo)}>
                  <Edit3 className="w-3 h-3 mr-1" />
                  {m.tieneUbicacion ? 'Editar' : 'Agregar'}
                </Button>
                {m.ubicacion?.ubicacion_id && (
                  <Button size="sm" variant="ghost" className="text-red-600" onClick={() => eliminarUbicacion(m.ubicacion!.ubicacion_id)} disabled={saving}>
                    <Trash2 className="w-3 h-3" />
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {medicos.length === 0 && !loadingMedicos && (
        <div className="text-center py-12 text-muted-foreground">
          <Search className="mx-auto h-10 w-10 mb-3" />
          <p>Busca un médico para gestionar su ubicación.</p>
        </div>
      )}

      {/* Modal de edición */}
      <Dialog open={!!editandoMedico} onOpenChange={() => setEditandoMedico(null)}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MapPin className="w-5 h-5" />
              {ubicaciones.find((u) => u.medico_id === editandoMedico)?.direccion ? 'Editar ubicación' : 'Agregar ubicación'}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium">Dirección del consultorio</label>
              <Input
                value={direccion}
                onChange={(e) => setDireccion(e.target.value)}
                placeholder="6a Avenida 12-45, Zona 10, Ciudad de Guatemala"
              />
            </div>
            <div className="flex gap-2">
              <Button size="sm" variant="outline" onClick={handleGeocodificar} disabled={geocodificando}>
                <Globe className="w-4 h-4 mr-1" />
                {geocodificando ? 'Buscando...' : 'Obtener coordenadas'}
              </Button>
            </div>

            {/* Mapa manual cuando la geocodificación falla */}
            {mostrarMapaManual && (
              <div className="bg-amber-50 border border-amber-200 rounded-lg p-3 space-y-3">
                <p className="text-sm text-amber-800 font-medium">
                  ⚠️ La dirección no fue encontrada automáticamente. Ubícala manualmente:
                </p>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    variant="outline"
                    className="flex-1"
                    onClick={() => window.open(`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(direccion)}`, '_blank')}
                  >
                    <Globe className="w-4 h-4 mr-1" />
                    Abrir en Google Maps ↗
                  </Button>
                </div>
                <p className="text-xs text-amber-700">
                  💡 <strong>En PC:</strong> Puedes usar el mapa de abajo directamente (arrastra con el mouse, zoom con la rueda, clic para mover el pin). O abre Google Maps para buscar la dirección.
                </p>
                <MapaInteractivo
                  lat={lat ? parseFloat(lat) : undefined}
                  lng={lng ? parseFloat(lng) : undefined}
                  onChange={(newLat, newLng) => {
                    setLat(newLat.toString())
                    setLng(newLng.toString())
                  }}
                  height="280px"
                />
                <div className="space-y-2">
                  <label className="text-xs font-medium text-amber-800">O pega la URL de Google Maps aquí:</label>
                  <div className="flex gap-2">
                    <Input
                      value={urlGoogleMaps}
                      onChange={(e) => setUrlGoogleMaps(e.target.value)}
                      placeholder="https://www.google.com/maps/@14.6349,-90.5069,15z"
                      className="text-sm"
                    />
                    <Button size="sm" variant="outline" onClick={extraerCoordenadasDeUrl}>
                      Extraer
                    </Button>
                  </div>
                </div>
              </div>
            )}

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-sm font-medium">Latitud</label>
                <Input value={lat} onChange={(e) => setLat(e.target.value)} placeholder="14.6349" />
              </div>
              <div>
                <label className="text-sm font-medium">Longitud</label>
                <Input value={lng} onChange={(e) => setLng(e.target.value)} placeholder="-90.5069" />
              </div>
            </div>
            <div>
              <label className="text-sm font-medium">Notas (opcional)</label>
              <Input
                value={notas}
                onChange={(e) => setNotas(e.target.value)}
                placeholder="Piso 3, oficina 301. Timbra dos veces."
              />
            </div>
            <div className="flex gap-3 pt-2">
              <Button variant="outline" className="flex-1" onClick={() => setEditandoMedico(null)}>
                Cancelar
              </Button>
              <Button className="flex-1" onClick={handleGuardar} disabled={saving}>
                {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <CheckCircle className="h-4 w-4 mr-1" />}
                Guardar
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
