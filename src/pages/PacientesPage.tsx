import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router'
import { usePacientes } from '@/hooks/usePacientes'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader } from '@/components/ui/card'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Users, Search, Plus, Pencil, Trash2, Loader2 } from 'lucide-react'

export default function PacientesPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const { pacientes, loading, createPaciente, updatePaciente, deletePaciente } = usePacientes()
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(searchParams.get('nuevo') === 'true')
  const [editing, setEditing] = useState<number | null>(null)
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    nombre: '', apellido: '', fecha_nacimiento: '', genero: '',
    telefono: '', email: '', direccion: '',
    emergencia_nombre: '', emergencia_telefono: '', alergias: '', notas: ''
  })

  const filtered = pacientes.filter(p =>
    (p.nombre + ' ' + p.apellido).toLowerCase().includes(search.toLowerCase()) ||
    (p.telefono || '').includes(search)
  )

  const [formError, setFormError] = useState('')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setFormError('')
    if (editing) {
      const { error } = await updatePaciente(editing, form)
      if (error) {
        setFormError(typeof error === 'string' ? error : 'Error al actualizar paciente')
        setSaving(false)
        return
      }
      setEditing(null)
    } else {
      const { error } = await createPaciente(form)
      if (error) {
        setFormError(typeof error === 'string' ? error : 'Error al guardar paciente. Verifica que completaste nombre y apellido.')
        setSaving(false)
        return
      }
    }
    setForm({ nombre: '', apellido: '', fecha_nacimiento: '', genero: '', telefono: '', email: '', direccion: '', emergencia_nombre: '', emergencia_telefono: '', alergias: '', notas: '' })
    setShowForm(false)
    setSaving(false)
  }

  const startEdit = (p: typeof pacientes[0]) => {
    setEditing(p.id)
    setForm({
      nombre: p.nombre, apellido: p.apellido, fecha_nacimiento: p.fecha_nacimiento || '',
      genero: p.genero || '', telefono: p.telefono || '', email: p.email || '',
      direccion: p.direccion || '', emergencia_nombre: p.emergencia_nombre || '',
      emergencia_telefono: p.emergencia_telefono || '', alergias: p.alergias || '', notas: p.notas || ''
    })
    setShowForm(true)
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-[#1a2a3a]">Pacientes</h1>
          <p className="text-[#8a9aaa] mt-1">Gestion de pacientes</p>
        </div>
        <Button onClick={() => { setShowForm(true); setEditing(null); setForm({ nombre: '', apellido: '', fecha_nacimiento: '', genero: '', telefono: '', email: '', direccion: '', emergencia_nombre: '', emergencia_telefono: '', alergias: '', notas: '' }) }} className="bg-[#1E5C8E] hover:bg-[#3A8ABF]">
          <Plus className="h-4 w-4 mr-2" /> Nuevo Paciente
        </Button>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-[#8a9aaa]" />
            <Input
              placeholder="Buscar por nombre o telefono..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-10"
            />
          </div>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" /></div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-12 text-[#8a9aaa]">
              <Users className="h-12 w-12 mx-auto mb-3 opacity-50" />
              <p>No hay pacientes registrados</p>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nombre</TableHead>
                  <TableHead>Telefono</TableHead>
                  <TableHead>Email</TableHead>
                  <TableHead>Nacimiento</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((p) => (
                  <TableRow key={p.id} className="cursor-pointer hover:bg-[#e8f0f8]" onClick={() => navigate(`/pacientes/${p.id}/detalle`)}>
                    <TableCell className="font-medium">{p.nombre} {p.apellido}</TableCell>
                    <TableCell>{p.telefono || '-'}</TableCell>
                    <TableCell>{p.email || '-'}</TableCell>
                    <TableCell>{p.fecha_nacimiento || '-'}</TableCell>
                    <TableCell className="text-right">
                      <Button variant="ghost" size="sm" onClick={(e) => { e.stopPropagation(); startEdit(p) }}>
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button variant="ghost" size="sm" onClick={(e) => { e.stopPropagation(); deletePaciente(p.id) }}>
                        <Trash2 className="h-4 w-4 text-red-500" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={showForm} onOpenChange={setShowForm}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editing ? 'Editar Paciente' : 'Nuevo Paciente'}</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2"><Label>Nombre *</Label><Input value={form.nombre} onChange={e => setForm({...form, nombre: e.target.value})} required /></div>
              <div className="space-y-2"><Label>Apellido *</Label><Input value={form.apellido} onChange={e => setForm({...form, apellido: e.target.value})} required /></div>
              <div className="space-y-2"><Label>Fecha Nacimiento</Label><Input type="date" value={form.fecha_nacimiento} onChange={e => setForm({...form, fecha_nacimiento: e.target.value})} /></div>
              <div className="space-y-2"><Label>Genero</Label>
                <select className="w-full border rounded-md h-10 px-3" value={form.genero} onChange={e => setForm({...form, genero: e.target.value})}>
                  <option value="">Seleccionar</option><option value="masculino">Masculino</option><option value="femenino">Femenino</option><option value="otro">Otro</option>
                </select>
              </div>
              <div className="space-y-2"><Label>Telefono</Label><Input value={form.telefono} onChange={e => setForm({...form, telefono: e.target.value})} placeholder="+502 1234 5678" /></div>
              <div className="space-y-2"><Label>Email</Label><Input type="email" value={form.email} onChange={e => setForm({...form, email: e.target.value})} /></div>
              <div className="space-y-2 col-span-2"><Label>Direccion</Label><Input value={form.direccion} onChange={e => setForm({...form, direccion: e.target.value})} /></div>
              <div className="space-y-2"><Label>Contacto Emergencia</Label><Input value={form.emergencia_nombre} onChange={e => setForm({...form, emergencia_nombre: e.target.value})} /></div>
              <div className="space-y-2"><Label>Telefono Emergencia</Label><Input value={form.emergencia_telefono} onChange={e => setForm({...form, emergencia_telefono: e.target.value})} /></div>
              <div className="space-y-2 col-span-2"><Label>Alergias</Label><Input value={form.alergias} onChange={e => setForm({...form, alergias: e.target.value})} /></div>
              <div className="space-y-2 col-span-2"><Label>Notas</Label><textarea className="w-full border rounded-md p-2 min-h-[80px]" value={form.notas} onChange={e => setForm({...form, notas: e.target.value})} /></div>
            </div>
            {formError && (
              <p className="text-sm text-red-500 bg-red-50 p-2 rounded">{formError}</p>
            )}
            <div className="flex justify-end gap-3">
              <Button type="button" variant="outline" onClick={() => { setShowForm(false); setFormError('') }}>Cancelar</Button>
              <Button type="submit" className="bg-[#1E5C8E] hover:bg-[#3A8ABF]" disabled={saving}>
                {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {editing ? 'Actualizar' : 'Guardar'}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
