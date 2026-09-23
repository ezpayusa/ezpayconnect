import { useState, useEffect } from 'react'
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { MapPin, Mail, Phone, Briefcase, User, Save, X, Pencil, Palette } from 'lucide-react'
import { FormPersonalizacion } from '@/components/personalizacion/FormPersonalizacion'
import { camposPerfilCambiados, type FormPerfil } from '@/proveedor/lib/perfilEmpresa'
import type { EmpresaProveedora, CuentaProveedor } from '@/proveedor/types/proveedor.types'

// `tipo` NO se edita acá (columna privilegiada; el guard de la mig 322 la bloquea). El form solo
// contiene los campos de PERFIL. Seed vacío: el useEffect lo carga desde `empresa` en cuanto llega.
const formVacio: FormPerfil = {
  nombre_empresa: '',
  ruc_nit: '',
  ciudad: '',
  direccion: '',
  email_contacto: '',
  telefono: '',
}

const snapshotEmpresa = (e: EmpresaProveedora | null | undefined): FormPerfil => ({
  nombre_empresa: e?.nombre_empresa ?? '',
  ruc_nit: e?.ruc_nit ?? '',
  ciudad: e?.ciudad ?? '',
  direccion: e?.direccion ?? '',
  email_contacto: e?.email_contacto ?? '',
  telefono: e?.telefono ?? '',
})

const mismoForm = (a: FormPerfil, b: FormPerfil): boolean =>
  (Object.keys(a) as (keyof FormPerfil)[]).every((k) => a[k] === b[k])

export default function ProveedorPerfilPage() {
  const { empresa, cuenta, actualizarEmpresa, actualizarCuenta, isEditor } = useProveedorAuth()
  const [editando, setEditando] = useState(false)
  const [saving, setSaving] = useState(false)

  const [formEmpresa, setFormEmpresa] = useState<FormPerfil>(formVacio)
  const [formCuenta, setFormCuenta] = useState({ nombre_completo: '' })

  // Sincroniza el form con `empresa`/`cuenta` MIENTRAS no se esté editando. Así, cuando el fetch
  // asíncrono de useProveedorAuth resuelve (o al cancelar), el form arranca con los valores REALES —
  // esto es lo que evita la pérdida de datos: el form ya no nace vacío y no se pisa lo cargado.
  // Devolver `prev` cuando no cambió nada hace que React se saltee el re-render (no suma ruido).
  useEffect(() => {
    if (editando) return
    setFormEmpresa((prev) => {
      const next = snapshotEmpresa(empresa)
      return mismoForm(prev, next) ? prev : next
    })
    setFormCuenta((prev) => {
      const next = { nombre_completo: cuenta?.nombre_completo ?? '' }
      return prev.nombre_completo === next.nombre_completo ? prev : next
    })
  }, [empresa, cuenta, editando])

  const handleGuardar = async () => {
    setSaving(true)
    // Guardado defensivo: solo los campos de perfil que cambiaron (diff con whitelist). Si no cambió
    // nada, no se toca la empresa.
    const cambiosEmpresa = camposPerfilCambiados(empresa, formEmpresa)
    let okEmpresa = true
    if (Object.keys(cambiosEmpresa).length > 0) {
      okEmpresa = await actualizarEmpresa(cambiosEmpresa as Partial<EmpresaProveedora>)
    }

    // El nombre del representante sigue el mismo criterio: solo si cambió y no quedó vacío.
    let okCuenta = true
    const nombre = formCuenta.nombre_completo.trim()
    if (nombre && nombre !== (cuenta?.nombre_completo ?? '')) {
      okCuenta = await actualizarCuenta({ nombre_completo: nombre } as Partial<CuentaProveedor>)
    }

    if (okEmpresa && okCuenta) {
      setEditando(false)
    }
    setSaving(false)
  }

  const handleEditar = () => {
    // Congela el form con los valores actuales de empresa/cuenta al entrar en edición.
    setFormEmpresa(snapshotEmpresa(empresa))
    setFormCuenta({ nombre_completo: cuenta?.nombre_completo ?? '' })
    setEditando(true)
  }

  const handleCancelar = () => {
    // Al salir de edición, el useEffect re-siembra el form desde empresa/cuenta.
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
          <Button variant="outline" size="sm" onClick={handleEditar} disabled={!empresa}>
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
                  {/* Tipo es de solo lectura: columna privilegiada, la cambia únicamente el admin de
                      EzPay (el guard de la mig 322 la bloquea para el proveedor). */}
                  <Label>Tipo</Label>
                  <p className="flex h-9 items-center px-3 text-sm text-muted-foreground capitalize">
                    {empresa?.tipo?.replace('_', ' ') || '-'}
                  </p>
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
