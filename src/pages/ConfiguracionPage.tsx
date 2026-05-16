import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { useAuth } from '@/hooks/useAuth'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Save, User, Building2, Bell, Shield, Palette } from 'lucide-react'

export default function ConfiguracionPage() {
  const { user } = useAuth()
  const [loading, setLoading] = useState(false)
  const [activeTab, setActiveTab] = useState('perfil')

  const handleSave = () => {
    toast.success('Configuración guardada')
  }

  return (
    <div className="container mx-auto px-4 py-6 max-w-4xl">
      <h1 className="text-2xl font-bold mb-6">Configuración</h1>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList className="mb-6">
          <TabsTrigger value="perfil" className="flex items-center gap-2">
            <User className="h-4 w-4" /> Perfil
          </TabsTrigger>
          <TabsTrigger value="clinica" className="flex items-center gap-2">
            <Building2 className="h-4 w-4" /> Clínica
          </TabsTrigger>
          <TabsTrigger value="notificaciones" className="flex items-center gap-2">
            <Bell className="h-4 w-4" /> Notificaciones
          </TabsTrigger>
          <TabsTrigger value="seguridad" className="flex items-center gap-2">
            <Shield className="h-4 w-4" /> Seguridad
          </TabsTrigger>
          <TabsTrigger value="apariencia" className="flex items-center gap-2">
            <Palette className="h-4 w-4" /> Apariencia
          </TabsTrigger>
        </TabsList>

        <TabsContent value="perfil">
          <Card>
            <CardHeader>
              <CardTitle>Información del Perfil</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Nombre</Label>
                  <Input placeholder="Tu nombre" defaultValue={user?.nombre || ''} />
                </div>
                <div className="space-y-2">
                  <Label>Email</Label>
                  <Input placeholder="tu@email.com" defaultValue={user?.email || ''} disabled />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Teléfono</Label>
                <Input placeholder="+502 1234 5678" />
              </div>
              <Button onClick={handleSave} className="bg-[#1E5C8E]">
                <Save className="h-4 w-4 mr-2" /> Guardar cambios
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="clinica">
          <Card>
            <CardHeader>
              <CardTitle>Información de la Clínica</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label>Nombre de la clínica</Label>
                <Input placeholder="Nombre de tu clínica" />
              </div>
              <div className="space-y-2">
                <Label>Dirección</Label>
                <Input placeholder="Dirección completa" />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Teléfono</Label>
                  <Input placeholder="Teléfono de la clínica" />
                </div>
                <div className="space-y-2">
                  <Label>Email</Label>
                  <Input placeholder="clinica@email.com" />
                </div>
              </div>
              <Button onClick={handleSave} className="bg-[#1E5C8E]">
                <Save className="h-4 w-4 mr-2" /> Guardar cambios
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="notificaciones">
          <Card>
            <CardHeader>
              <CardTitle>Preferencias de Notificaciones</CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium">Notificaciones por email</p>
                  <p className="text-sm text-muted-foreground">Recibir notificaciones importantes por correo</p>
                </div>
                <Switch defaultChecked />
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium">Notificaciones push</p>
                  <p className="text-sm text-muted-foreground">Recibir notificaciones en el navegador</p>
                </div>
                <Switch defaultChecked />
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium">Recordatorios de citas</p>
                  <p className="text-sm text-muted-foreground">Enviar recordatorios automáticos a pacientes</p>
                </div>
                <Switch defaultChecked />
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium">Alertas de inventario</p>
                  <p className="text-sm text-muted-foreground">Notificar cuando el inventario esté bajo</p>
                </div>
                <Switch />
              </div>
              <Button onClick={handleSave} className="bg-[#1E5C8E]">
                <Save className="h-4 w-4 mr-2" /> Guardar cambios
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="seguridad">
          <Card>
            <CardHeader>
              <CardTitle>Seguridad de la Cuenta</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label>Contraseña actual</Label>
                <Input type="password" placeholder="••••••••" />
              </div>
              <div className="space-y-2">
                <Label>Nueva contraseña</Label>
                <Input type="password" placeholder="••••••••" />
              </div>
              <div className="space-y-2">
                <Label>Confirmar nueva contraseña</Label>
                <Input type="password" placeholder="••••••••" />
              </div>
              <div className="flex items-center justify-between pt-4">
                <div>
                  <p className="font-medium">Autenticación de dos factores</p>
                  <p className="text-sm text-muted-foreground">Añadir una capa extra de seguridad</p>
                </div>
                <Switch />
              </div>
              <Button onClick={handleSave} className="bg-[#1E5C8E]">
                <Save className="h-4 w-4 mr-2" /> Guardar cambios
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="apariencia">
          <Card>
            <CardHeader>
              <CardTitle>Apariencia</CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium">Modo oscuro</p>
                  <p className="text-sm text-muted-foreground">Cambiar entre tema claro y oscuro</p>
                </div>
                <Switch />
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium">Tamaño de fuente</p>
                  <p className="text-sm text-muted-foreground">Ajustar el tamaño del texto</p>
                </div>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm">Pequeño</Button>
                  <Button variant="default" size="sm" className="bg-[#1E5C8E]">Normal</Button>
                  <Button variant="outline" size="sm">Grande</Button>
                </div>
              </div>
              <Button onClick={handleSave} className="bg-[#1E5C8E]">
                <Save className="h-4 w-4 mr-2" /> Guardar cambios
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}