import { useState } from 'react'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { MapPin, Mail, Phone, Briefcase, User, Save, X, Pencil, Palette } from 'lucide-react'
import { FormPersonalizacion } from '@/components/personalizacion/FormPersonalizacion'

export default function ProveedorPerfilPage() {
  const { empresa, cuenta, actualizarEmpresa, actualizarCuenta, isEditor } = useProveedorAuth()
  const [editando, setEditando] = useState(false)
  const [saving, setSaving] = useState(false)

  const [formEmpresa, setFormEmpresa] = useState({
    nombre_empresa: empresa?.nombre_empresa || '',
    tipo: empresa?.tipo || 'farmacia',
    ruc_nit: empresa?.ruc_nit || '',
    ciudad: empresa?.ciudad || '',
    direccion: empresa?.direccion || '',
    email_contacto: empresa?.email_contacto || '',
    telefono: empresa?.telefono || '',
  })

  const [formCuenta, setFormCuenta] = useState({
    nombre_completo: cuenta?.nombre_completo || '',
  })

  const handleGuardar = async () => {
    setSaving(true)
    const okEmpresa = await actualizarEmpresa(formEmpresa)
    const okCuenta = await actualizarCuenta(formCuenta)
    if (okEmpresa && okCuenta) {
      setEditando(false)
    }
    setSaving(false)
  }

  const handleCancelar = () => {
    setFormEmpresa({
      nombre_empresa: empresa?.nombre_empresa || '',
      tipo: empresa?.tipo || 'farmacia',
      ruc_nit: empresa?.ruc_nit || '',
      ciudad: empresa?.ciudad || '',
      direccion: empresa?.direccion || '',
      email_contacto: empresa?.email_contacto || '',
      telefono: empresa?.telefono || '',
    })
    setFormCuenta({
      nombre_completo: cuenta?.nombre_completo || '',
    })
    setEditando(false)
  }

  return (
    <div className="space-y-6 max-w-2xl mx-auto">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Perfil de Empresa</h1>
          <p className="text-sm text-muted-foreground">Información de tu empresa registrada</p>
        </div>
        {isEditor && !editando && (
          <Button variant="outline" size="sm" onClick={() => setEditando(true)}>
            <Pencil className="h-4 w-4 mr-1" />
            Editar
          </Button>
        )}
        {editando && (
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={handleCancelar} disabled={saving}>
              <X className="h-4 w-4 mr-1" />
              Cancelar
            </Button>
            <Button size="sm" onClick={handleGuardar} disabled={saving}>
              <Save className="h-4 w-4 mr-1" />
              {saving ? 'Guardando...' : 'Guardar'}
            </Button>
          </div>
        )}
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center gap-2">
            <MapPin className="h-5 w-5 text-[#1E5C8E]" />
            {editando ? 'Datos de la empresa' : (empresa?.nombre_empresa || 'Empresa')}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          {editando ? (
            <div className="space-y-4">
              <div className="grid grid-cols-1 gap-2">
                <Label htmlFor="nombre_empresa">Nombre de empresa</Label>
                <Input
                  id="nombre_empresa"
                  value={formEmpresa.nombre_empresa}
                  onChange={(e) => setFormEmpresa((prev) => ({ ...prev, nombre_empresa: e.target.value }))}
                />
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="tipo">Tipo</Label>
                  <select
                    id="tipo"
                    className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                    value={formEmpresa.tipo}
                    onChange={(e) => setFormEmpresa((prev) => ({ ...prev, tipo: e.target.value as any }))}
                  >
                    <option value="farmacia">Farmacia</option>
                    <option value="laboratorio_farmaceutico">Laboratorio farmacéutico</option>
                    <option value="laboratorio_clinico">Laboratorio clínico</option>
                    <option value="empresa_afin">Empresa afín</option>
                  </select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="ruc_nit">RUC / NIT</Label>
                  <Input
                    id="ruc_nit"
                    value={formEmpresa.ruc_nit}
                    onChange={(e) => setFormEmpresa((prev) => ({ ...prev, ruc_nit: e.target.value }))}
                  />
                </div>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="email_contacto">Email de contacto</Label>
                  <Input
                    id="email_contacto"
                    type="email"
                    value={formEmpresa.email_contacto}
                    onChange={(e) => setFormEmpresa((prev) => ({ ...prev, email_contacto: e.target.value }))}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="telefono">Teléfono</Label>
                  <Input
                    id="telefono"
                    value={formEmpresa.telefono}
                    onChange={(e) => setFormEmpresa((prev) => ({ ...prev, telefono: e.target.value }))}
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="direccion">Dirección</Label>
                <Input
                  id="direccion"
                  value={formEmpresa.direccion}
                  onChange={(e) => setFormEmpresa((prev) => ({ ...prev, direccion: e.target.value }))}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="ciudad">Ciudad</Label>
                <Input
                  id="ciudad"
                  value={formEmpresa.ciudad}
                  onChange={(e) => setFormEmpresa((prev) => ({ ...prev, ciudad: e.target.value }))}
                />
              </div>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-3">
                <Briefcase className="h-4 w-4 text-muted-foreground" />
                <span className="text-muted-foreground w-24">Tipo</span>
                <span className="font-medium capitalize">{empresa?.tipo?.replace('_', ' ') || '-'}</span>
              </div>
              <div className="flex items-center gap-3">
                <Mail className="h-4 w-4 text-muted-foreground" />
                <span className="text-muted-foreground w-24">Email</span>
                <span className="font-medium">{empresa?.email_contacto || '-'}</span>
              </div>
              <div className="flex items-center gap-3">
                <Phone className="h-4 w-4 text-muted-foreground" />
                <span className="text-muted-foreground w-24">Teléfono</span>
                <span className="font-medium">{empresa?.telefono || '-'}</span>
              </div>
              <div className="flex items-center gap-3">
                <MapPin className="h-4 w-4 text-muted-foreground" />
                <span className="text-muted-foreground w-24">Ubicación</span>
                <span className="font-medium">
                  {[empresa?.direccion, empresa?.ciudad].filter(Boolean).join(', ') || '-'}
                </span>
              </div>
              {empresa?.ruc_nit && (
                <div className="flex items-center gap-3">
                  <MapPin className="h-4 w-4 text-muted-foreground" />
                  <span className="text-muted-foreground w-24">RUC/NIT</span>
                  <span className="font-medium">{empresa.ruc_nit}</span>
                </div>
              )}
            </>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center gap-2">
            <User className="h-5 w-5 text-[#1E5C8E]" />
            Representante
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          {editando ? (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="nombre_completo">Nombre completo</Label>
                <Input
                  id="nombre_completo"
                  value={formCuenta.nombre_completo}
                  onChange={(e) => setFormCuenta((prev) => ({ ...prev, nombre_completo: e.target.value }))}
                />
              </div>
              <div className="flex items-center gap-3">
                <span className="text-muted-foreground w-24">Email</span>
                <span className="font-medium">{cuenta?.email || '-'}</span>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-muted-foreground w-24">Rol</span>
                <span className="font-medium capitalize">{cuenta?.rol_en_empresa || '-'}</span>
              </div>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-3">
                <span className="text-muted-foreground w-24">Nombre</span>
                <span className="font-medium">{cuenta?.nombre_completo || '-'}</span>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-muted-foreground w-24">Email</span>
                <span className="font-medium">{cuenta?.email || '-'}</span>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-muted-foreground w-24">Rol</span>
                <span className="font-medium capitalize">{cuenta?.rol_en_empresa || '-'}</span>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center gap-2">
            <Palette className="h-5 w-5 text-[#1E5C8E]" /> Personalización
          </CardTitle>
          <p className="text-sm text-muted-foreground">Logo y colores del panel. Se aplican tras la aprobación de un administrador.</p>
        </CardHeader>
        <CardContent>
          <FormPersonalizacion tenantTipo="empresa_proveedora" tenantId={empresa?.id} actual={empresa ?? null} />
        </CardContent>
      </Card>
    </div>
  )
}
