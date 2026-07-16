import { useEffect, useMemo, useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { useLaboratorio } from '@/laboratorio/hooks/useLaboratorio'
import { useLaboratorioPermisos } from '@/laboratorio/hooks/useLaboratorioPermisos'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { UserPlus, Loader2, AlertTriangle } from 'lucide-react'

export default function LabWalkInPage() {
  const { crearWalkIn, catalogo, fetchCatalogo } = useLaboratorio()
  const { tienePermiso, loading: permLoading } = useLaboratorioPermisos()
  const navigate = useNavigate()
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [otros, setOtros] = useState('')
  const [form, setForm] = useState({
    paciente_nombre: '', paciente_documento: '', paciente_telefono: '', instrucciones: '', prioridad: 'normal',
  })
  const [saving, setSaving] = useState(false)

  useEffect(() => { fetchCatalogo() }, [fetchCatalogo])

  const porCategoria = useMemo(() => {
    const acc: Record<string, typeof catalogo> = {}
    catalogo.filter((c) => c.activo).forEach((c) => { (acc[c.categoria || 'Sin categoría'] ||= []).push(c) })
    return acc
  }, [catalogo])

  const toggle = (nombre: string) => {
    setSel((prev) => { const n = new Set(prev); n.has(nombre) ? n.delete(nombre) : n.add(nombre); return n })
  }

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    const examenes = [...sel, ...otros.split('\n').map((s) => s.trim()).filter(Boolean)]
    if (!form.paciente_nombre.trim() || examenes.length === 0) return
    setSaving(true)
    const ok = await crearWalkIn({
      examenes,
      instrucciones: form.instrucciones.trim() || undefined,
      prioridad: form.prioridad,
      paciente_nombre: form.paciente_nombre.trim(),
      paciente_documento: form.paciente_documento.trim() || undefined,
      paciente_telefono: form.paciente_telefono.trim() || undefined,
    })
    setSaving(false)
    if (ok) navigate('/laboratorio/ordenes')
  }

  const total = sel.size + otros.split('\n').map((s) => s.trim()).filter(Boolean).length

  if (!permLoading && !tienePermiso('walkin_registrar')) {
    return (
      <div className="p-8 text-center">
        <AlertTriangle className="mx-auto h-12 w-12 text-amber-500 mb-4" />
        <h2 className="text-xl font-semibold">Acceso restringido</h2>
        <p className="text-muted-foreground mt-2">No tienes permiso para registrar pacientes walk-in.</p>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2 text-[#0c2a26]">
          <UserPlus className="h-7 w-7 text-[#0E7C6B]" /> Paciente walk-in
        </h1>
        <p className="text-sm text-muted-foreground">Registra una orden para un paciente que llega sin orden médica.</p>
      </div>

      <form onSubmit={submit} className="space-y-6">
        <Card>
          <CardHeader><CardTitle className="text-lg">Datos del paciente</CardTitle></CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-1 md:col-span-2">
                <Label>Nombre del paciente *</Label>
                <Input value={form.paciente_nombre} onChange={(e) => setForm({ ...form, paciente_nombre: e.target.value })} required />
              </div>
              <div className="space-y-1">
                <Label>Documento</Label>
                <Input value={form.paciente_documento} onChange={(e) => setForm({ ...form, paciente_documento: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>Teléfono</Label>
                <Input value={form.paciente_telefono} onChange={(e) => setForm({ ...form, paciente_telefono: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>Prioridad</Label>
                <select className="w-full h-10 rounded-md border border-input bg-background px-3 text-sm"
                  value={form.prioridad} onChange={(e) => setForm({ ...form, prioridad: e.target.value })}>
                  <option value="normal">Normal</option>
                  <option value="urgente">Urgente</option>
                </select>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="text-lg">Exámenes a realizar</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            {catalogo.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                Tu catálogo está vacío. Agrega exámenes en <Link to="/laboratorio/catalogo" className="text-[#0E7C6B] underline">Catálogo</Link>, o escríbelos abajo en "Otros".
              </p>
            ) : (
              Object.entries(porCategoria).map(([cat, items]) => (
                <div key={cat}>
                  <p className="text-xs font-semibold text-muted-foreground uppercase mb-1">{cat}</p>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-1">
                    {items.map((c) => (
                      <label key={c.id} className="flex items-center gap-2 p-2 rounded-lg hover:bg-gray-50 cursor-pointer text-sm">
                        <input type="checkbox" checked={sel.has(c.nombre)} onChange={() => toggle(c.nombre)} className="accent-[#0E7C6B] h-4 w-4" />
                        {c.nombre}
                      </label>
                    ))}
                  </div>
                </div>
              ))
            )}
            <div className="space-y-1">
              <Label>Otros exámenes (uno por línea)</Label>
              <Textarea rows={2} value={otros} onChange={(e) => setOtros(e.target.value)} placeholder="Examen no listado…" />
            </div>
            <div className="space-y-1">
              <Label>Instrucciones / observaciones</Label>
              <Textarea rows={2} value={form.instrucciones} onChange={(e) => setForm({ ...form, instrucciones: e.target.value })} />
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={() => navigate('/laboratorio/ordenes')}>Cancelar</Button>
          <Button type="submit" className="bg-[#0E7C6B] hover:bg-[#0a5e51]" disabled={saving || !form.paciente_nombre.trim() || total === 0}>
            {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null} Registrar orden ({total})
          </Button>
        </div>
      </form>
    </div>
  )
}
