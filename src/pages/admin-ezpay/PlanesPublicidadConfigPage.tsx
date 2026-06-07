import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { usePlanesPublicidadConfig } from '@/hooks/admin/usePlanesPublicidadConfig'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import {
  ArrowLeft,
  Save,
  Loader2,
  RefreshCw,
  Plus,
  DollarSign,
  Globe,
  Megaphone,
} from 'lucide-react'

export default function PlanesPublicidadConfigPage() {
  const navigate = useNavigate()
  const {
    configs,
    paises,
    planesBase,
    loading,
    saving,
    updateConfig,
    crearConfigParaPais,
  } = usePlanesPublicidadConfig()

  const [filtroPais, setFiltroPais] = useState<string>('todos')
  const [editando, setEditando] = useState<Record<number, { precio: string; moneda: string; activo: boolean }>>({})
  const [paisSeleccionado, setPaisSeleccionado] = useState('')

  const configsFiltradas =
    filtroPais === 'todos'
      ? configs
      : configs.filter((c) => c.pais_id === filtroPais)

  const handleEdit = (id: number, precio: number, moneda: string, activo: boolean) => {
    setEditando((prev) => ({
      ...prev,
      [id]: { precio: String(precio), moneda, activo },
    }))
  }

  const handleSave = async (id: number) => {
    const e = editando[id]
    if (!e) return
    const ok = await updateConfig(id, {
      precio_local: parseFloat(e.precio) || 0,
      moneda_local: e.moneda,
      activo: e.activo,
    })
    if (ok) {
      setEditando((prev) => {
        const next = { ...prev }
        delete next[id]
        return next
      })
    }
  }

  const handleCrearParaPais = async () => {
    if (!paisSeleccionado) return
    await crearConfigParaPais(paisSeleccionado)
    setPaisSeleccionado('')
  }

  const paisesSinConfig = paises.filter(
    (p) => !configs.some((c) => c.pais_id === p.id)
  )

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Precios de Publicidad por País</h1>
            <p className="text-sm text-muted-foreground">
              Configura precios locales y monedas para cada plan de publicidad
            </p>
          </div>
        </div>
        <Button variant="outline" onClick={() => window.location.reload()}>
          <RefreshCw className="h-4 w-4 mr-2" /> Recargar
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-purple-100 rounded-lg">
                <Globe className="h-5 w-5 text-purple-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Países Activos</p>
                <p className="text-xl font-bold">{paises.length}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-100 rounded-lg">
                <Megaphone className="h-5 w-5 text-blue-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Configuraciones</p>
                <p className="text-xl font-bold">{configs.length}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-emerald-100 rounded-lg">
                <DollarSign className="h-5 w-5 text-emerald-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Países sin Config</p>
                <p className="text-xl font-bold">{paisesSinConfig.length}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-amber-100 rounded-lg">
                <Megaphone className="h-5 w-5 text-amber-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Planes Base</p>
                <p className="text-xl font-bold">{planesBase.length}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Crear config para país sin config */}
      {paisesSinConfig.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Crear configuración para país nuevo</CardTitle>
          </CardHeader>
          <CardContent className="flex gap-3">
            <Select value={paisSeleccionado} onValueChange={setPaisSeleccionado}>
              <SelectTrigger className="w-64">
                <SelectValue placeholder="Seleccionar país..." />
              </SelectTrigger>
              <SelectContent>
                {paisesSinConfig.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.nombre} ({p.codigo}) — {p.moneda}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Button onClick={handleCrearParaPais} disabled={!paisSeleccionado || saving}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4 mr-2" />}
              Crear planes
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Filtro */}
      <div className="flex items-center gap-3">
        <span className="text-sm text-gray-500">Filtrar por país:</span>
        <Select value={filtroPais} onValueChange={setFiltroPais}>
          <SelectTrigger className="w-56">
            <SelectValue placeholder="Todos los países" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="todos">Todos los países</SelectItem>
            {paises.map((p) => (
              <SelectItem key={p.id} value={p.id}>
                {p.nombre} ({p.codigo})
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Tabla */}
      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
      ) : configsFiltradas.length === 0 ? (
        <Card className="bg-gray-50 border-dashed">
          <CardContent className="p-8 text-center">
            <Megaphone className="h-10 w-10 text-gray-300 mx-auto mb-3" />
            <h3 className="text-lg font-semibold text-gray-700">No hay configuraciones</h3>
            <p className="text-sm text-muted-foreground">
              Selecciona un país arriba para crear sus planes de publicidad.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="border rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-500">País</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Plan</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Precio Local</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Moneda</th>
                <th className="px-4 py-3 text-left font-medium text-gray-500">Estado</th>
                <th className="px-4 py-3 text-right font-medium text-gray-500">Acciones</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {configsFiltradas.map((c) => {
                const isEditing = !!editando[c.id]
                const e = editando[c.id]

                return (
                  <tr key={c.id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <Globe className="h-4 w-4 text-gray-400" />
                        <span className="font-medium">{c.pais_nombre}</span>
                        <Badge variant="outline" className="text-xs">{c.pais_codigo}</Badge>
                      </div>
                    </td>
                    <td className="px-4 py-3">{c.plan_nombre}</td>
                    <td className="px-4 py-3">
                      {isEditing ? (
                        <Input
                          type="number"
                          value={e.precio}
                          onChange={(ev) =>
                            setEditando((prev) => ({
                              ...prev,
                              [c.id]: { ...prev[c.id], precio: ev.target.value },
                            }))
                          }
                          className="w-32 h-8"
                        />
                      ) : (
                        <span className="font-mono">
                          {new Intl.NumberFormat('es').format(c.precio_local)}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {isEditing ? (
                        <Input
                          value={e.moneda}
                          onChange={(ev) =>
                            setEditando((prev) => ({
                              ...prev,
                              [c.id]: { ...prev[c.id], moneda: ev.target.value },
                            }))
                          }
                          className="w-20 h-8 uppercase"
                          maxLength={3}
                        />
                      ) : (
                        <Badge variant="secondary">{c.moneda_local}</Badge>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {isEditing ? (
                        <div className="flex items-center gap-2">
                          <Switch
                            checked={e.activo}
                            onCheckedChange={(checked) =>
                              setEditando((prev) => ({
                                ...prev,
                                [c.id]: { ...prev[c.id], activo: checked },
                              }))
                            }
                          />
                          <span className="text-xs">{e.activo ? 'Activo' : 'Inactivo'}</span>
                        </div>
                      ) : c.activo ? (
                        <Badge className="bg-emerald-100 text-emerald-700">Activo</Badge>
                      ) : (
                        <Badge className="bg-gray-100 text-gray-700">Inactivo</Badge>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right">
                      {isEditing ? (
                        <Button size="sm" onClick={() => handleSave(c.id)} disabled={saving}>
                          {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5 mr-1" />}
                          Guardar
                        </Button>
                      ) : (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => handleEdit(c.id, c.precio_local, c.moneda_local, c.activo)}
                        >
                          Editar
                        </Button>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
