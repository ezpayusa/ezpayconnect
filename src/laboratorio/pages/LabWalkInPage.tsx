import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useLaboratorio } from '@/laboratorio/hooks/useLaboratorio'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { UserPlus, Loader2 } from 'lucide-react'

export default function LabWalkInPage() {
  const { crearWalkIn } = useLaboratorio()
  const navigate = useNavigate()
  const [form, setForm] = useState({
    paciente_nombre: '', paciente_documento: '', paciente_telefono: '',
    tipo: '', descripcion: '', prioridad: 'normal',
  })
  const [saving, setSaving] = useState(false)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.paciente_nombre.trim() || !form.tipo.trim()) return
    setSaving(true)
    const ok = await crearWalkIn({
      tipo: form.tipo.trim(),
      descripcion: form.descripcion.trim() || undefined,
      prioridad: form.prioridad,
      paciente_nombre: form.paciente_nombre.trim(),
      paciente_documento: form.paciente_documento.trim() || undefined,
      paciente_telefono: form.paciente_telefono.trim() || undefined,
    })
    setSaving(false)
    if (ok) navigate('/laboratorio/ordenes')
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2 text-[#0c2a26]">
          <UserPlus className="h-7 w-7 text-[#0E7C6B]" /> Paciente walk-in
        </h1>
        <p className="text-sm text-muted-foreground">
          Registra una orden para un paciente que llega sin haber sido referido por un médico.
        </p>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-lg">Datos del paciente y del examen</CardTitle></CardHeader>
        <CardContent>
          <form onSubmit={submit} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-1 md:col-span-2">
                <Label>Nombre del paciente *</Label>
                <Input value={form.paciente_nombre} onChange={(e) => setForm({ ...form, paciente_nombre: e.target.value })} required />
              </div>
              <div className="space-y-1">
                <Label>Documento / identificación</Label>
                <Input value={form.paciente_documento} onChange={(e) => setForm({ ...form, paciente_documento: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>Teléfono</Label>
                <Input value={form.paciente_telefono} onChange={(e) => setForm({ ...form, paciente_telefono: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>Tipo de examen *</Label>
                <Input value={form.tipo} onChange={(e) => setForm({ ...form, tipo: e.target.value })}
                  placeholder="Ej: Hemograma completo" required />
              </div>
              <div className="space-y-1">
                <Label>Prioridad</Label>
                <select className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
                  value={form.prioridad} onChange={(e) => setForm({ ...form, prioridad: e.target.value })}>
                  <option value="normal">Normal</option>
                  <option value="urgente">Urgente</option>
                </select>
              </div>
              <div className="space-y-1 md:col-span-2">
                <Label>Indicaciones / descripción</Label>
                <Textarea rows={3} value={form.descripcion} onChange={(e) => setForm({ ...form, descripcion: e.target.value })} />
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => navigate('/laboratorio/ordenes')}>Cancelar</Button>
              <Button type="submit" className="bg-[#0E7C6B] hover:bg-[#0a5e51]" disabled={saving || !form.paciente_nombre.trim() || !form.tipo.trim()}>
                {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null} Registrar orden
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
