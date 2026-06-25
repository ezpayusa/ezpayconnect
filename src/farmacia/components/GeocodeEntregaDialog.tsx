import { useState } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { MapPinned, Loader2 } from 'lucide-react'
import MapaInteractivo from '@/components/MapaInteractivo'
import { toast } from 'sonner'
import type { EntregaMonitoreo } from '@/farmacia/hooks/useEntregasMonitoreo'

interface Props {
  entrega: EntregaMonitoreo
  geocodificar: (direccion: string) => Promise<{ lat: number; lng: number } | null>
  guardarDireccion: (entregaId: number, direccion: string, lat: number | null, lng: number | null) => Promise<void>
  onSaved: () => void
  onClose: () => void
}

// Control del GESTOR (gate entregas_gestionar) para corregir dirección + geolocalizar. Best-effort: si el geocoder
// falla, NO bloquea — se puede ajustar el pin a mano o guardar sin coords. La dirección solo se usa dentro de scope.
export default function GeocodeEntregaDialog({ entrega, geocodificar, guardarDireccion, onSaved, onClose }: Props) {
  const [direccion, setDireccion] = useState(entrega.direccion_entrega ?? '')
  const [lat, setLat] = useState<number | null>(entrega.lat)
  const [lng, setLng] = useState<number | null>(entrega.lng)
  const [geocoding, setGeocoding] = useState(false)
  const [saving, setSaving] = useState(false)

  const onGeolocalizar = async () => {
    if (!direccion.trim()) { toast.error('Escribí una dirección'); return }
    setGeocoding(true)
    const coords = await geocodificar(direccion.trim())
    setGeocoding(false)
    if (coords) {
      setLat(coords.lat); setLng(coords.lng)
      toast.success('Ubicación encontrada — ajustá el pin si hace falta')
    } else {
      toast.warning('No se pudo geolocalizar. Ajustá el pin a mano o guardá sin coordenadas.')
    }
  }

  const onGuardar = async () => {
    if (!direccion.trim()) { toast.error('La dirección no puede quedar vacía'); return }
    setSaving(true)
    try {
      await guardarDireccion(entrega.id, direccion.trim(), lat, lng)
      toast.success('Dirección actualizada')
      onSaved()
      onClose()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo guardar')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-[#1E5C8E]">
            <MapPinned className="h-5 w-5" /> Corregir dirección · Entrega #{entrega.id}
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1">
            <Label className="text-xs">Dirección de entrega</Label>
            <div className="flex gap-2">
              <Input value={direccion} onChange={(e) => setDireccion(e.target.value)} placeholder="Dirección del paciente" />
              <Button type="button" variant="outline" onClick={onGeolocalizar} disabled={geocoding || saving}
                className="border-[#1E5C8E] text-[#1E5C8E] hover:bg-[#e8f0f8] shrink-0">
                {geocoding ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Geolocalizar'}
              </Button>
            </div>
          </div>

          <MapaInteractivo lat={lat} lng={lng} onChange={(la, ln) => { setLat(la); setLng(ln) }} height="240px" />
          <p className="text-xs text-[#8a9aaa]">
            {lat != null && lng != null ? 'Tocá el mapa para ajustar el pin.' : 'Sin coordenadas aún — geolocalizá o tocá el mapa.'}
          </p>

          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
            <Button type="button" className="bg-[#1E5C8E] hover:bg-[#3A8ABF]" onClick={onGuardar} disabled={saving}>
              {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Guardar
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
