import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { supabase } from '@/lib/supabase';
import { 
  ArrowLeft, 
  Plus, 
  Search, 
  RefreshCw, 
  Trash2, 
  Users,
  Shield,
  UserCheck,
  UserPlus
} from 'lucide-react';

interface UsuarioConRoles {
  id: string;
  email: string;
  nombre_completo: string;
  nombre: string;
  roles: { id: string; nombre: string; nivel: number }[];
}

interface Rol {
  id: string;
  nombre: string;
  descripcion: string;
  nivel: number;
}

export default function AsignacionRolesPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [usuarios, setUsuarios] = useState<UsuarioConRoles[]>([]);
  const [roles, setRoles] = useState<Rol[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [dialogoAsignar, setDialogoAsignar] = useState<string | null>(null);
  const [dialogoNuevoEmpleado, setDialogoNuevoEmpleado] = useState(false);
  const [rolSeleccionado, setRolSeleccionado] = useState('');

  const [nuevoEmpleado, setNuevoEmpleado] = useState({
    email: '',
    password: '',
    nombre_completo: '',
    nombre: '',
    rol: 'cliente',
  });

  const cargarDatos = async () => {
    setLoading(true);

    // Cargar roles
    const { data: rolesData, error: rolesError } = await supabase
      .from('roles')
      .select('*')
      .order('nivel', { ascending: false });

    if (rolesError) {
      console.error('Error cargando roles:', rolesError);
    } else {
      setRoles(rolesData || []);
    }

    // Cargar usuarios SIN el join complejo
    const { data: usuariosData, error: usuariosError } = await supabase
      .from('perfiles')
      .select('id, email, nombre_completo, nombre')
      .order('nombre_completo');

    if (usuariosError) {
      console.error('Error cargando usuarios:', usuariosError);
      setUsuarios([]);
    } else {
      // Cargar roles de cada usuario por separado
      const usuariosConRoles = await Promise.all(
        (usuariosData || []).map(async (u: any) => {
          const { data: rolesUsuario } = await supabase
            .from('usuario_roles')
            .select(`
              rol_id,
              roles(id, nombre, nivel)
            `)
            .eq('usuario_id', u.id)
            .eq('activo', true);

          return {
            id: u.id,
            email: u.email,
            nombre_completo: u.nombre_completo,
            nombre: u.nombre,
            roles: (rolesUsuario || [])
              .filter((ur: any) => ur.roles)
              .map((ur: any) => ({
                id: ur.roles.id,
                nombre: ur.roles.nombre,
                nivel: ur.roles.nivel,
              })),
          };
        })
      );
      setUsuarios(usuariosConRoles);
    }

    setLoading(false);
  };

  useEffect(() => {
    if (!adminLoading && isAdmin) {
      cargarDatos();
    }
  }, [adminLoading, isAdmin]);

  const handleAsignarRol = async () => {
    if (!dialogoAsignar || !rolSeleccionado) return;

    const { data: userData } = await supabase.auth.getUser();

    const { error } = await supabase
      .from('usuario_roles')
      .insert({
        usuario_id: dialogoAsignar,
        rol_id: rolSeleccionado,
        asignado_por: userData.user?.id,
        fecha_asignacion: new Date().toISOString(),
        activo: true,
      });

    if (error) {
      alert('Error asignando rol: ' + error.message);
    } else {
      setDialogoAsignar(null);
      setRolSeleccionado('');
      cargarDatos();
    }
  };

  const handleQuitarRol = async (usuarioId: string, rolId: string) => {
    const { error } = await supabase
      .from('usuario_roles')
      .update({ activo: false })
      .eq('usuario_id', usuarioId)
      .eq('rol_id', rolId);

    if (error) {
      alert('Error quitando rol: ' + error.message);
    } else {
      cargarDatos();
    }
  };

  const handleCrearEmpleado = async () => {
    if (!nuevoEmpleado.email || !nuevoEmpleado.password || !nuevoEmpleado.nombre_completo) {
      alert('Email, contraseña y nombre son obligatorios');
      return;
    }

    try {
      // 1. Crear usuario en Auth
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: nuevoEmpleado.email,
        password: nuevoEmpleado.password,
        options: {
          data: {
            nombre_completo: nuevoEmpleado.nombre_completo,
          }
        }
      });

      if (authError) {
        alert('Error creando usuario en Auth: ' + authError.message);
        return;
      }

      const userId = authData.user?.id;
      if (!userId) {
        alert('Error: No se pudo obtener el ID del usuario.\n\nVerifica que la confirmación de email esté DESACTIVADA en Supabase (Authentication → Settings → Email Auth → Enable email confirmations = OFF)');
        return;
      }

      // 2. Esperar un momento para que el usuario se cree en auth.users
      await new Promise(resolve => setTimeout(resolve, 1000));

      // 3. Crear perfil en perfiles
      const { error: perfilError } = await supabase
        .from('perfiles')
        .insert({
          id: userId,
          email: nuevoEmpleado.email,
          nombre_completo: nuevoEmpleado.nombre_completo,
          nombre: nuevoEmpleado.nombre || nuevoEmpleado.nombre_completo,
          rol: nuevoEmpleado.rol,
          activo: true,
        });

      if (perfilError) {
        alert('Error creando perfil: ' + perfilError.message + '\n\nEl usuario fue creado en Auth pero no en perfiles. Contacta al administrador.');
        return;
      }

      // 4. Asignar rol en usuario_roles
      const rolSeleccionado = roles.find(r => r.nombre === nuevoEmpleado.rol);
      if (rolSeleccionado) {
        const { data: userData } = await supabase.auth.getUser();
        const { error: rolError } = await supabase
          .from('usuario_roles')
          .insert({
            usuario_id: userId,
            rol_id: rolSeleccionado.id,
            asignado_por: userData.user?.id,
            fecha_asignacion: new Date().toISOString(),
            activo: true,
          });

        if (rolError) {
          console.warn('Error asignando rol (no crítico):', rolError.message);
        }
      }

      // Éxito
      setDialogoNuevoEmpleado(false);
      setNuevoEmpleado({ email: '', password: '', nombre_completo: '', nombre: '', rol: 'cliente' });
      cargarDatos();
      alert('Empleado creado exitosamente');

    } catch (error: any) {
      alert('Error inesperado: ' + error.message);
    }
  };

  const getRolColor = (nivel: number) => {
    if (nivel >= 5) return 'bg-purple-100 text-purple-700';
    if (nivel >= 4) return 'bg-blue-100 text-blue-700';
    if (nivel >= 3) return 'bg-cyan-100 text-cyan-700';
    if (nivel >= 2) return 'bg-emerald-100 text-emerald-700';
    return 'bg-gray-100 text-gray-700';
  };

  const usuariosFiltrados = usuarios.filter(u => 
    !search || 
    u.nombre_completo?.toLowerCase().includes(search.toLowerCase()) ||
    u.email?.toLowerCase().includes(search.toLowerCase())
  );

  const totalUsuarios = usuarios.length;
  const usuariosConRol = usuarios.filter(u => u.roles.length > 0).length;

  if (adminLoading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    );
  }

  if (!isAdmin) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Card className="max-w-md">
          <CardContent className="pt-6 text-center">
            <h2 className="text-xl font-bold mb-2">Acceso restringido</h2>
            <p className="text-sm text-muted-foreground mb-4">Necesitas rol de administrador.</p>
            <Button onClick={() => navigate('/dashboard')}>Volver</Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Asignacion de Roles</h1>
            <p className="text-sm text-muted-foreground">Gestiona los roles de los usuarios del sistema</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={cargarDatos}>
            <RefreshCw className="h-4 w-4 mr-2" /> Recargar
          </Button>
          <Button onClick={() => setDialogoNuevoEmpleado(true)} className="bg-green-600 hover:bg-green-700">
            <UserPlus className="h-4 w-4 mr-2" /> Nuevo Empleado
          </Button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Users className="h-5 w-5 text-[#1E5C8E]" />
              <p className="text-sm text-muted-foreground">Total Usuarios</p>
            </div>
            <p className="text-2xl font-bold">{totalUsuarios}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <UserCheck className="h-5 w-5 text-green-600" />
              <p className="text-sm text-muted-foreground">Con Rol Asignado</p>
            </div>
            <p className="text-2xl font-bold">{usuariosConRol}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Shield className="h-5 w-5 text-purple-600" />
              <p className="text-sm text-muted-foreground">Roles Disponibles</p>
            </div>
            <p className="text-2xl font-bold">{roles.length}</p>
          </CardContent>
        </Card>
      </div>

      {/* Filtros */}
      <div className="flex gap-4 mb-6">
        <div className="flex-1">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input 
              placeholder="Buscar usuario..." 
              value={search} 
              onChange={(e) => setSearch(e.target.value)} 
              className="pl-9" 
            />
          </div>
        </div>
      </div>

      {/* Tabla */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Usuarios y sus Roles</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Usuario</TableHead>
                  <TableHead>Roles Asignados</TableHead>
                  <TableHead className="text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {usuariosFiltrados.map((usuario) => (
                  <TableRow key={usuario.id}>
                    <TableCell>
                      <div>
                        <p className="font-medium">{usuario.nombre_completo || 'Sin nombre'}</p>
                        <p className="text-sm text-muted-foreground">{usuario.email}</p>
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {usuario.roles.length === 0 && (
                          <span className="text-sm text-muted-foreground">Sin roles asignados</span>
                        )}
                        {usuario.roles.map((rol) => (
                          <Badge key={rol.id} className={getRolColor(rol.nivel)}>
                            {rol.nombre.replace('_', ' ')}
                            <button 
                              onClick={() => handleQuitarRol(usuario.id, rol.id)}
                              className="ml-1 hover:text-red-500"
                              title="Quitar rol"
                            >
                              ×
                            </button>
                          </Badge>
                        ))}
                      </div>
                    </TableCell>
                    <TableCell className="text-right">
                      <Button 
                        variant="ghost" 
                        size="sm" 
                        onClick={() => setDialogoAsignar(usuario.id)}
                        className="text-[#1E5C8E]"
                      >
                        <Plus className="h-4 w-4 mr-1" /> Asignar Rol
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
                {usuariosFiltrados.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={3} className="text-center py-8 text-muted-foreground">
                      No se encontraron usuarios
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Modal Asignar Rol */}
      <Dialog open={!!dialogoAsignar} onOpenChange={() => setDialogoAsignar(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Shield className="h-5 w-5 text-[#1E5C8E]" />
              Asignar Rol
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Seleccionar Rol</Label>
              <Select value={rolSeleccionado} onValueChange={setRolSeleccionado}>
                <SelectTrigger>
                  <SelectValue placeholder="Selecciona un rol" />
                </SelectTrigger>
                <SelectContent>
                  {roles.map((rol) => (
                    <SelectItem key={rol.id} value={rol.id}>
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium">{rol.nombre.replace('_', ' ')}</span>
                        <span className="text-xs text-muted-foreground">(Nivel {rol.nivel})</span>
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoAsignar(null)}>Cancelar</Button>
              <Button 
                onClick={handleAsignarRol} 
                disabled={!rolSeleccionado}
                className="bg-[#1E5C8E] hover:bg-[#164a70]"
              >
                <Plus className="h-4 w-4 mr-2" /> Asignar Rol
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Modal Nuevo Empleado */}
      <Dialog open={dialogoNuevoEmpleado} onOpenChange={setDialogoNuevoEmpleado}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <UserPlus className="h-5 w-5 text-green-600" />
              Nuevo Empleado
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="emp_email">Email *</Label>
              <Input id="emp_email" type="email" value={nuevoEmpleado.email} onChange={(e) => setNuevoEmpleado({...nuevoEmpleado, email: e.target.value})} placeholder="empleado@ezpay.com" />
            </div>
            <div>
              <Label htmlFor="emp_password">Contraseña Temporal *</Label>
              <Input id="emp_password" type="password" value={nuevoEmpleado.password} onChange={(e) => setNuevoEmpleado({...nuevoEmpleado, password: e.target.value})} placeholder="Minimo 6 caracteres" />
            </div>
            <div>
              <Label htmlFor="emp_nombre">Nombre Completo *</Label>
              <Input id="emp_nombre" value={nuevoEmpleado.nombre_completo} onChange={(e) => setNuevoEmpleado({...nuevoEmpleado, nombre_completo: e.target.value})} placeholder="Nombre completo" />
            </div>
            <div>
              <Label htmlFor="emp_nombre_corto">Nombre Corto</Label>
              <Input id="emp_nombre_corto" value={nuevoEmpleado.nombre} onChange={(e) => setNuevoEmpleado({...nuevoEmpleado, nombre: e.target.value})} placeholder="Nombre corto o alias" />
            </div>
            <div>
              <Label htmlFor="emp_rol">Rol</Label>
              <Select value={nuevoEmpleado.rol} onValueChange={(v) => setNuevoEmpleado({...nuevoEmpleado, rol: v})}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {roles.map((rol) => (
                    <SelectItem key={rol.id} value={rol.nombre}>{rol.nombre.replace('_', ' ')} (Nivel {rol.nivel})</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoNuevoEmpleado(false)}>Cancelar</Button>
              <Button 
                onClick={handleCrearEmpleado} 
                disabled={!nuevoEmpleado.email || !nuevoEmpleado.password || !nuevoEmpleado.nombre_completo}
                className="bg-green-600 hover:bg-green-700"
              >
                <UserPlus className="h-4 w-4 mr-2" /> Crear Empleado
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
