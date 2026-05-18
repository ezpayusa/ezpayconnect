import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { supabase } from '@/lib/supabase';
import { 
  ArrowLeft, 
  RefreshCw, 
  Plus, 
  Shield, 
  Users,
  Key,
  Save,
  X,
  Edit,
  Trash2
} from 'lucide-react';

interface Rol {
  id: string;
  nombre: string;
  descripcion: string;
  permisos: string[];
  nivel: number;
  activo: boolean;
  usuarios_count?: number;
}

const PERMISOS_DISPONIBLES = [
  { id: '*', label: 'Acceso Total', descripcion: 'Todos los permisos' },
  { id: 'planes.read', label: 'Ver Planes', descripcion: 'Ver planes y precios' },
  { id: 'planes.write', label: 'Editar Planes', descripcion: 'Crear y modificar planes' },
  { id: 'usuarios.read', label: 'Ver Usuarios', descripcion: 'Ver lista de usuarios' },
  { id: 'usuarios.write', label: 'Editar Usuarios', descripcion: 'Crear y modificar usuarios' },
  { id: 'finanzas.read', label: 'Ver Finanzas', descripcion: 'Ver reportes financieros' },
  { id: 'reportes.read', label: 'Ver Reportes', descripcion: 'Ver reportes y analytics' },
  { id: 'comisiones.read', label: 'Ver Comisiones', descripcion: 'Ver comisiones por país' },
  { id: 'clientes.read', label: 'Ver Clientes', descripcion: 'Ver clientes y suscripciones' },
  { id: 'clientes.write', label: 'Editar Clientes', descripcion: 'Gestionar clientes' },
  { id: 'tickets.read', label: 'Ver Tickets', descripcion: 'Ver tickets de soporte' },
  { id: 'tickets.write', label: 'Editar Tickets', descripcion: 'Responder tickets' },
  { id: 'perfil.read', label: 'Ver Perfil', descripcion: 'Ver perfil propio' },
  { id: 'perfil.write', label: 'Editar Perfil', descripcion: 'Editar perfil propio' },
  { id: 'mis_planes.read', label: 'Ver Mis Planes', descripcion: 'Ver suscripciones propias' },
];

export default function RolesPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [roles, setRoles] = useState<Rol[]>([]);
  const [loading, setLoading] = useState(true);
  const [dialogoNuevo, setDialogoNuevo] = useState(false);
  const [dialogoEditar, setDialogoEditar] = useState<Rol | null>(null);
  const [nuevoRol, setNuevoRol] = useState({
    nombre: '',
    descripcion: '',
    permisos: [] as string[],
    nivel: 1,
  });

  const cargarRoles = async () => {
    setLoading(true);

    const { data, error } = await supabase
      .from('roles')
      .select('*')
      .order('nivel', { ascending: false });

    if (error) {
      console.error('Error:', error.message);
      alert('Error al cargar roles: ' + error.message);
    } else {
      // Obtener conteo de usuarios por rol
      const rolesConConteo = await Promise.all((data || []).map(async (rol: Rol) => {
        const { count } = await supabase
          .from('usuario_roles')
          .select('*', { count: 'exact', head: true })
          .eq('rol_id', rol.id)
          .eq('activo', true);
        return { ...rol, usuarios_count: count || 0 };
      }));
      setRoles(rolesConConteo);
    }
    setLoading(false);
  };

 useEffect(() => {
  if (!adminLoading && !isAdmin) {
    navigate('/dashboard');
    return;
  }
  cargarRoles();
}, [adminLoading, isAdmin, navigate]);

  const handleCrearRol = async () => {
    if (!nuevoRol.nombre) {
      alert('El nombre del rol es obligatorio');
      return;
    }

    const { error } = await supabase
      .from('roles')
      .insert({
        nombre: nuevoRol.nombre.toLowerCase().replace(/\s+/g, '_'),
        descripcion: nuevoRol.descripcion,
        permisos: nuevoRol.permisos,
        nivel: nuevoRol.nivel,
        activo: true,
      });

    if (error) {
      alert('Error: ' + error.message);
    } else {
      alert('Rol creado correctamente');
      setDialogoNuevo(false);
      setNuevoRol({ nombre: '', descripcion: '', permisos: [], nivel: 1 });
      cargarRoles();
    }
  };

  const handleActualizarRol = async () => {
    if (!dialogoEditar) return;

    const { error } = await supabase
      .from('roles')
      .update({
        descripcion: dialogoEditar.descripcion,
        permisos: dialogoEditar.permisos,
        nivel: dialogoEditar.nivel,
        activo: dialogoEditar.activo,
      })
      .eq('id', dialogoEditar.id);

    if (error) {
      alert('Error: ' + error.message);
    } else {
      alert('Rol actualizado');
      setDialogoEditar(null);
      cargarRoles();
    }
  };

  const handleEliminarRol = async (rolId: string) => {
    if (!confirm('¿Eliminar este rol? Los usuarios asignados perderán este permiso.')) return;

    const { error } = await supabase
      .from('roles')
      .delete()
      .eq('id', rolId);

    if (error) {
      alert('Error: ' + error.message);
    } else {
      alert('Rol eliminado');
      cargarRoles();
    }
  };

  const togglePermiso = (permisoId: string, rol: Rol, isEdit: boolean = false) => {
    const currentPermisos = isEdit && dialogoEditar ? [...dialogoEditar.permisos] : [...nuevoRol.permisos];

    if (currentPermisos.includes(permisoId)) {
      const filtered = currentPermisos.filter(p => p !== permisoId);
      if (isEdit && dialogoEditar) {
        setDialogoEditar({ ...dialogoEditar, permisos: filtered });
      } else {
        setNuevoRol({ ...nuevoRol, permisos: filtered });
      }
    } else {
      const added = [...currentPermisos, permisoId];
      if (isEdit && dialogoEditar) {
        setDialogoEditar({ ...dialogoEditar, permisos: added });
      } else {
        setNuevoRol({ ...nuevoRol, permisos: added });
      }
    }
  };

  const getNivelColor = (nivel: number) => {
    if (nivel >= 5) return 'bg-red-100 text-red-700';
    if (nivel >= 4) return 'bg-orange-100 text-orange-700';
    if (nivel >= 3) return 'bg-yellow-100 text-yellow-700';
    if (nivel >= 2) return 'bg-blue-100 text-blue-700';
    return 'bg-gray-100 text-gray-700';
  };

  if (adminLoading) return <div className="flex justify-center p-8">Verificando permisos...</div>;
  if (!isAdmin) return null;

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Gestión de Roles</h1>
            <p className="text-sm text-muted-foreground">Administra roles y permisos del sistema</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={cargarRoles}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
          <Button onClick={() => setDialogoNuevo(true)} className="bg-[#1E5C8E] hover:bg-[#164a70]"><Plus className="h-4 w-4 mr-2" /> Nuevo Rol</Button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Shield className="h-5 w-5 text-[#1E5C8E]" />
              <p className="text-sm text-muted-foreground">Total Roles</p>
            </div>
            <p className="text-2xl font-bold">{roles.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Key className="h-5 w-5 text-orange-600" />
              <p className="text-sm text-muted-foreground">Permisos</p>
            </div>
            <p className="text-2xl font-bold">{PERMISOS_DISPONIBLES.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Users className="h-5 w-5 text-green-600" />
              <p className="text-sm text-muted-foreground">Usuarios con Rol</p>
            </div>
            <p className="text-2xl font-bold">{roles.reduce((sum, r) => sum + (r.usuarios_count || 0), 0)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Shield className="h-5 w-5 text-purple-600" />
              <p className="text-sm text-muted-foreground">Nivel Máx</p>
            </div>
            <p className="text-2xl font-bold">{roles.length > 0 ? Math.max(...roles.map(r => r.nivel)) : 0}</p>
          </CardContent>
        </Card>
      </div>

      {/* Lista de roles */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
        {roles.map((rol) => (
          <Card key={rol.id} className={rol.activo ? 'border-[#1E5C8E]/20' : 'border-gray-200 opacity-75'}>
            <CardContent className="pt-6">
              <div className="flex justify-between items-start mb-3">
                <div>
                  <h3 className="text-lg font-bold capitalize">{rol.nombre.replace(/_/g, ' ')}</h3>
                  <p className="text-sm text-muted-foreground">{rol.descripcion}</p>
                </div>
                <Badge className={getNivelColor(rol.nivel)}>Nivel {rol.nivel}</Badge>
              </div>

              <div className="flex items-center gap-4 mb-3 text-sm">
                <div className="flex items-center gap-1">
                  <Users className="h-4 w-4 text-muted-foreground" />
                  <span>{rol.usuarios_count} usuarios</span>
                </div>
                <div className="flex items-center gap-1">
                  <Key className="h-4 w-4 text-muted-foreground" />
                  <span>{rol.permisos?.length || 0} permisos</span>
                </div>
              </div>

              <div className="flex flex-wrap gap-1 mb-4">
                {(rol.permisos || []).slice(0, 4).map((permiso) => (
                  <Badge key={permiso} variant="outline" className="text-xs">
                    {permiso}
                  </Badge>
                ))}
                {(rol.permisos || []).length > 4 && (
                  <Badge variant="outline" className="text-xs">+{(rol.permisos || []).length - 4} más</Badge>
                )}
              </div>

              <div className="flex gap-2 pt-3 border-t">
                <Button size="sm" variant="outline" onClick={() => setDialogoEditar(rol)}>
                  <Edit className="h-3 w-3 mr-1" /> Editar
                </Button>
                <Button size="sm" variant="ghost" className="text-red-500" onClick={() => handleEliminarRol(rol.id)}>
                  <Trash2 className="h-3 w-3" />
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Dialogo Nuevo Rol */}
      <Dialog open={dialogoNuevo} onOpenChange={setDialogoNuevo}>
        <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Shield className="h-5 w-5 text-[#1E5C8E]" />
              Nuevo Rol
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="nombre">Nombre del Rol *</Label>
              <Input id="nombre" value={nuevoRol.nombre} onChange={(e) => setNuevoRol({...nuevoRol, nombre: e.target.value})} placeholder="Ej: marketing_manager" />
            </div>
            <div>
              <Label htmlFor="descripcion">Descripción</Label>
              <Input id="descripcion" value={nuevoRol.descripcion} onChange={(e) => setNuevoRol({...nuevoRol, descripcion: e.target.value})} placeholder="Descripción del rol..." />
            </div>
            <div>
              <Label htmlFor="nivel">Nivel (1-5)</Label>
              <Input id="nivel" type="number" min={1} max={5} value={nuevoRol.nivel} onChange={(e) => setNuevoRol({...nuevoRol, nivel: parseInt(e.target.value)})} />
            </div>
            <div>
              <Label>Permisos</Label>
              <div className="grid grid-cols-1 gap-2 mt-2 max-h-60 overflow-y-auto">
                {PERMISOS_DISPONIBLES.map((permiso) => (
                  <div key={permiso.id} className="flex items-center gap-2 p-2 rounded hover:bg-gray-50">
                    <input 
                      type="checkbox" 
                      checked={nuevoRol.permisos.includes(permiso.id)}
                      onChange={() => togglePermiso(permiso.id, nuevoRol as any)}
                      className="h-4 w-4"
                    />
                    <div>
                      <p className="text-sm font-medium">{permiso.label}</p>
                      <p className="text-xs text-muted-foreground">{permiso.descripcion}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoNuevo(false)}><X className="h-4 w-4 mr-1" /> Cancelar</Button>
              <Button onClick={handleCrearRol} className="bg-[#1E5C8E] hover:bg-[#164a70]"><Save className="h-4 w-4 mr-1" /> Crear Rol</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Dialogo Editar Rol */}
      <Dialog open={!!dialogoEditar} onOpenChange={() => setDialogoEditar(null)}>
        <DialogContent className="max-w-lg max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Shield className="h-5 w-5 text-[#1E5C8E]" />
              Editar Rol: {dialogoEditar?.nombre}
            </DialogTitle>
          </DialogHeader>
          {dialogoEditar && (
            <div className="space-y-4">
              <div>
                <Label>Descripción</Label>
                <Input value={dialogoEditar.descripcion} onChange={(e) => setDialogoEditar({...dialogoEditar, descripcion: e.target.value})} />
              </div>
              <div>
                <Label>Nivel (1-5)</Label>
                <Input type="number" min={1} max={5} value={dialogoEditar.nivel} onChange={(e) => setDialogoEditar({...dialogoEditar, nivel: parseInt(e.target.value)})} />
              </div>
              <div className="flex items-center gap-2">
                <Switch checked={dialogoEditar.activo} onCheckedChange={(checked) => setDialogoEditar({...dialogoEditar, activo: checked})} />
                <Label>Activo</Label>
              </div>
              <div>
                <Label>Permisos</Label>
                <div className="grid grid-cols-1 gap-2 mt-2 max-h-60 overflow-y-auto">
                  {PERMISOS_DISPONIBLES.map((permiso) => (
                    <div key={permiso.id} className="flex items-center gap-2 p-2 rounded hover:bg-gray-50">
                      <input 
                        type="checkbox" 
                        checked={dialogoEditar.permisos.includes(permiso.id)}
                        onChange={() => togglePermiso(permiso.id, dialogoEditar, true)}
                        className="h-4 w-4"
                      />
                      <div>
                        <p className="text-sm font-medium">{permiso.label}</p>
                        <p className="text-xs text-muted-foreground">{permiso.descripcion}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setDialogoEditar(null)}><X className="h-4 w-4 mr-1" /> Cancelar</Button>
                <Button onClick={handleActualizarRol} className="bg-[#1E5C8E] hover:bg-[#164a70]"><Save className="h-4 w-4 mr-1" /> Guardar</Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}