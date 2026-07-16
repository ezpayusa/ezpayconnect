import { useEffect, useState } from 'react'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { useLaboratorioPermisos } from '@/laboratorio/hooks/useLaboratorioPermisos'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { FlaskConical, Loader2 } from 'lucide-react'

export default function LabPerfilPage() {
  const { empresa, actualizarEmpresa } = useProveedorAuth()
  const { tienePermiso } = useLaboratorioPermisos()
  const puedeEditar = tienePermiso('config_empresa')
  const [form, setForm] = useState({ nombre_empresa: '', email_contacto: '', telefono: '', ciudad: '', direccion: '', ruc_nit: '' })
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (empresa) setForm({
      nombre_empresa: empresa.nombre_empresa || '',
      email_contacto: empresa.email_contacto || '',
      telefono: empresa.telefono || '',
      ciudad: empresa.ciudad || '',
      direccion: empresa.direccion || '',
      ruc_nit: empresa.ruc_nit || '',
    })
  }, [empresa])

  const guardar = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    await actualizarEmpresa(form)
    setSaving(false)
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2 text-[#0c2a26]">
        <FlaskConical className="h-7 w-7 text-[#0E7C6B]" /> Perfil del laboratorio
      </h1>
      <Card>
        <CardHeader><CardTitle className="text-lg">Datos del laboratorio</CardTitle></CardHeader>
        <CardContent>
          <form onSubmit={guardar}>
            <fieldset disabled={!puedeEditar} className="space-y-4 min-w-0 border-0 p-0 m-0">
            <div className="space-y-1">
              <Label>Nombre del laboratorio</Label>
              <Input value={form.nombre_empresa} onChange={(e) => setForm({ ...form, nombre_empresa: e.target.value })} />
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-1">
                <Label>Email de contacto</Label>
                <Input type="email" value={form.email_contacto} onChange={(e) => setForm({ ...form, email_contacto: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>Teléfono</Label>
                <Input value={form.telefono} onChange={(e) => setForm({ ...form, telefono: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>Ciudad</Label>
                <Input value={form.ciudad} onChange={(e) => setForm({ ...form, ciudad: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>RUC / NIT</Label>
                <Input value={form.ruc_nit} onChange={(e) => setForm({ ...form, ruc_nit: e.target.value })} />
              </div>
              <div className="space-y-1 md:col-span-2">
                <Label>Dirección</Label>
                <Input value={form.direccion} onChange={(e) => setForm({ ...form, direccion: e.target.value })} />
              </div>
            </div>
            {puedeEditar && (
              <div className="flex justify-end">
                <Button type="submit" className="bg-[#0E7C6B] hover:bg-[#0a5e51]" disabled={saving}>
                  {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : null} Guardar
                </Button>
              </div>
            )}
            </fieldset>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
