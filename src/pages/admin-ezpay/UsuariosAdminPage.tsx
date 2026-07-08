import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';
import { supabase } from '@/lib/supabase';
import { 
  ArrowLeft, 
  Plus, 
  Search, 
  RefreshCw, 
  Edit,
  Users,
  UserCheck,
  UserX,
  Shield,
  Globe
} from 'lucide-react';

interface UsuarioAdmin {
  id: string;
  email: string;
  nombre_completo: string;
  nombre: string;
  rol: string;
  activo: boolean;
  created_at: string;
  rol_id?: string | null;
}

const ROLES_ADMIN = [
  { value: 'super_admin', label: 'Super Admin', nivel: 5 },
  { value: 'admin', label: 'Admin', nivel: 4 },
  { value: 'gerente', label: 'Gerente', nivel: 3 },
  { value: 'vendedor', label: 'Vendedor', nivel: 2 },
  { value: 'soporte', label: 'Soporte', nivel: 2 },
  { value: 'cliente', label: 'Cliente', nivel: 1 },
];

export default function UsuariosAdminPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [usuarios, setUsuarios] = useState<UsuarioAdmin[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filtroRol, setFiltroRol] = useState('todos');
  const [dialogoCrear, setDialogoCrear] = useState(false);
  const [dialogoEditar, setDialogoEditar] = useState<UsuarioAdmin | null>(null);
  const [dialogoDesactivar, setDialogoDesactivar] = useState<string | null>(null);
  const { paisId } = usePaisFiltro();

  const [nuevoUsuario, setNuevoUsuario] = useState({
    email: '',
    nombre_completo: '',
    nombre: '',
    rol: 'cliente',
    activo: true,
  });

  const cargarUsuarios = useCallback(async () => {
    setLoading(true);
    let query = supabase
      .from('perfiles')
      .select('*')
    if (paisId) query = query.eq('pais_id', paisId)
    const { data, error } = await query.order('created_at', { ascending: false });

    if (error) {
      console.error('Error cargando usuarios:', error);
    } else {
      setUsuarios(data || []);
    }
    setLoading(false);
  }, [paisId]);

  useEffect(() => {
    if (!adminLoading && isAdmin) {
      cargarUsuarios();
    }
  }, [adminLoading, isAdmin, cargarUsuarios]);

  const handleCrearUsuario = async () => {
    if (!nuevoUsuario.email || !nuevoUsuario.nombre_completo) {
      alert('Email y nombre son obligatorios');
      return;
    }

    const { error } = await supabase
      .from('perfiles')
      .insert({
        id: crypto.randomUUID(),
        email: nuevoUsuario.email,
        nombre_completo: nuevoUsuario.nombre_completo,
        nombre: nuevoUsuario.nombre || nuevoUsuario.nombre_completo,
        rol: nuevoUsuario.rol,
        activo: nuevoUsuario.activo,
      });

    if (error) {
      alert('Error creando usuario: ' + error.message);
    } else {
      setDialogoCrear(false);
      setNuevoUsuario({ email: '', nombre_completo: '', nombre: '', rol: 'cliente', activo: true });
      cargarUsuarios();
    }
  };

  const handleActualizarUsuario = async () => {
    if (!dialogoEditar) return;

    const { error } = await supabase
      .from('perfiles')
      .update({
        nombre_completo: dialogoEditar.nombre_completo,
        nombre: dialogoEditar.nombre,
        rol: dialogoEditar.rol,
        activo: dialogoEditar.activo,
      })
      .eq('id', dialogoEditar.id);

    if (error) {
      alert('Error actualizando: ' + error.message);
    } else {
      setDialogoEditar(null);
      cargarUsuarios();
    }
  };

  // Soft-delete: NUNCA DELETE físico (rompe FKs clínicas/auditoría: signos_vitales, auditoria_ia,
  // expediente_notas, pagos_proveedor son RESTRICT). Desactivar = activo=false, reversible (mismo que el Switch).
  const handleDesactivarUsuario = async (id: string) => {
    const { error } = await supabase
      .from('perfiles')
      .update({ activo: false })
      .eq('id', id);

    if (error) {
      alert('Error desactivando: ' + error.message);
    } else {
      setDialogoDesactivar(null);
      cargarUsuarios();
    }
  };

  const toggleActivo = async (usuario: UsuarioAdmin) => {
    const { error } = await supabase
      .from('perfiles')
      .update({ activo: !usuario.activo })
      .eq('id', usuario.id);

    if (error) {
      alert('Error: ' + error.message);
    } else {
      cargarUsuarios();
    }
  };

  const getRolColor = (rol: string) => {
    const colors: Record<string, string> = {
      super_admin: 'bg-purple-100 text-purple-700',
      admin: 'bg-blue-100 text-blue-700',
      gerente: 'bg-cyan-100 text-cyan-700',
      vendedor: 'bg-emerald-100 text-emerald-700',
      soporte: 'bg-amber-100 text-amber-700',
      cliente: 'bg-gray-100 text-gray-700',
    };
    return colors[rol] || 'bg-gray-100 text-gray-700';
  };

  const usuariosFiltrados = usuarios.filter(u => {
    const matchSearch = !search || 
      u.nombre_completo?.toLowerCase().includes(search.toLowerCase()) ||
      u.email?.toLowerCase().includes(search.toLowerCase()) ||
      u.rol?.toLowerCase().includes(search.toLowerCase());
    const matchRol = filtroRol === 'todos' || u.rol === filtroRol;
    return matchSearch && matchRol;
  });

  const totalUsuarios = usuarios.length;
  const usuariosActivos = usuarios.filter(u => u.activo).length;
  const usuariosPorRol = (rol: string) => usuarios.filter(u => u.rol === rol).length;

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
            <h1 className="text-2xl font-bold">Gestion de Usuarios</h1>
            <p className="text-sm text-muted-foreground">Administra usuarios del sistema EZPay</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={cargarUsuarios}>
            <RefreshCw className="h-4 w-4 mr-2" /> Recargar
          </Button>
          <Button onClick={() => setDialogoCrear(true)} className="bg-[#1E5C8E] hover:bg-[#164a70]">
            <Plus className="h-4 w-4 mr-2" /> Nuevo Usuario
          </Button>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
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
              <p className="text-sm text-muted-foreground">Activos</p>
            </div>
            <p className="text-2xl font-bold">{usuariosActivos}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <Shield className="h-5 w-5 text-purple-600" />
              <p className="text-sm text-muted-foreground">Admins</p>
            </div>
            <p className="text-2xl font-bold">{usuariosPorRol('super_admin') + usuariosPorRol('admin')}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="flex items-center gap-2 mb-2">
              <UserX className="h-5 w-5 text-red-500" />
              <p className="text-sm text-muted-foreground">Inactivos</p>
            </div>
            <p className="text-2xl font-bold">{totalUsuarios - usuariosActivos}</p>
          </CardContent>
        </Card>
      </div>

      {/* Filtros */}
      <div className="flex gap-4 mb-6">
        <div className="flex-1">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input 
              placeholder="Buscar por nombre, email o rol..." 
              value={search} 
              onChange={(e) => setSearch(e.target.value)} 
              className="pl-9" 
            />
          </div>
        </div>
        <Select value={filtroRol} onValueChange={setFiltroRol}>
          <SelectTrigger className="w-[180px]">
            <SelectValue placeholder="Filtrar por rol" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="todos">Todos los roles</SelectItem>
            {ROLES_ADMIN.map(r => (
              <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Tabla de Usuarios */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Usuarios del Sistema</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Usuario</TableHead>
                  <TableHead>Rol</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead>Fecha Registro</TableHead>
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
                      <Badge className={getRolColor(usuario.rol)}>
                        {usuario.rol?.replace('_', ' ') || 'cliente'}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <Switch 
                          checked={usuario.activo} 
                          onCheckedChange={() => toggleActivo(usuario)}
                        />
                        <span className={usuario.activo ? 'text-green-600' : 'text-gray-400'}>
                          {usuario.activo ? 'Activo' : 'Inactivo'}
                        </span>
                      </div>
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">
                      {new Date(usuario.created_at).toLocaleDateString('es-ES')}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button variant="ghost" size="icon" onClick={() => setDialogoEditar(usuario)}>
                        <Edit className="h-4 w-4" />
                      </Button>
                      {usuario.activo && (
                        <Button variant="ghost" size="icon" className="text-amber-600" title="Desactivar usuario" onClick={() => setDialogoDesactivar(usuario.id)}>
                          <UserX className="h-4 w-4" />
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
                {usuariosFiltrados.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={5} className="text-center py-8 text-muted-foreground">
                      No se encontraron usuarios
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Modal Crear Usuario */}
      <Dialog open={dialogoCrear} onOpenChange={setDialogoCrear}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Users className="h-5 w-5 text-[#1E5C8E]" />
              Nuevo Usuario
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="email">Email *</Label>
              <Input id="email" type="email" value={nuevoUsuario.email} onChange={(e) => setNuevoUsuario({...nuevoUsuario, email: e.target.value})} placeholder="usuario@ejemplo.com" />
            </div>
            <div>
              <Label htmlFor="nombre_completo">Nombre Completo *</Label>
              <Input id="nombre_completo" value={nuevoUsuario.nombre_completo} onChange={(e) => setNuevoUsuario({...nuevoUsuario, nombre_completo: e.target.value})} placeholder="Nombre completo" />
            </div>
            <div>
              <Label htmlFor="nombre">Nombre Corto</Label>
              <Input id="nombre" value={nuevoUsuario.nombre} onChange={(e) => setNuevoUsuario({...nuevoUsuario, nombre: e.target.value})} placeholder="Nombre corto o alias" />
            </div>
            <div>
              <Label htmlFor="rol">Rol</Label>
              <Select value={nuevoUsuario.rol} onValueChange={(v) => setNuevoUsuario({...nuevoUsuario, rol: v})}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ROLES_ADMIN.map(r => (
                    <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-center gap-2">
              <Switch checked={nuevoUsuario.activo} onCheckedChange={(checked) => setNuevoUsuario({...nuevoUsuario, activo: checked})} />
              <Label>Usuario activo</Label>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoCrear(false)}>Cancelar</Button>
              <Button onClick={handleCrearUsuario} disabled={!nuevoUsuario.email || !nuevoUsuario.nombre_completo} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                <Plus className="h-4 w-4 mr-2" /> Crear Usuario
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Modal Editar Usuario */}
      <Dialog open={!!dialogoEditar} onOpenChange={() => setDialogoEditar(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Edit className="h-5 w-5 text-[#1E5C8E]" />
              Editar Usuario
            </DialogTitle>
          </DialogHeader>
          {dialogoEditar && (
            <div className="space-y-4">
              <div>
                <Label>Email</Label>
                <Input value={dialogoEditar.email} disabled className="bg-gray-50" />
              </div>
              <div>
                <Label>Nombre Completo</Label>
                <Input value={dialogoEditar.nombre_completo} onChange={(e) => setDialogoEditar({...dialogoEditar, nombre_completo: e.target.value})} />
              </div>
              <div>
                <Label>Nombre Corto</Label>
                <Input value={dialogoEditar.nombre || ''} onChange={(e) => setDialogoEditar({...dialogoEditar, nombre: e.target.value})} />
              </div>
              <div>
                <Label>Rol</Label>
                <Select value={dialogoEditar.rol} onValueChange={(v) => setDialogoEditar({...dialogoEditar, rol: v})}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ROLES_ADMIN.map(r => (
                      <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex items-center gap-2">
                <Switch checked={dialogoEditar.activo} onCheckedChange={(checked) => setDialogoEditar({...dialogoEditar, activo: checked})} />
                <Label>Usuario activo</Label>
              </div>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setDialogoEditar(null)}>Cancelar</Button>
                <Button onClick={handleActualizarUsuario} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                  <Edit className="h-4 w-4 mr-2" /> Guardar Cambios
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Modal Confirmar Desactivacion (soft-delete: activo=false, reversible — nunca DELETE físico) */}
      <Dialog open={!!dialogoDesactivar} onOpenChange={() => setDialogoDesactivar(null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-center">Desactivar Usuario</DialogTitle>
          </DialogHeader>
          <div className="text-center py-4">
            <p className="text-muted-foreground mb-4">El usuario quedará inactivo y no podrá iniciar sesión. Podés reactivarlo cuando quieras.</p>
            <div className="flex justify-center gap-2">
              <Button variant="outline" onClick={() => setDialogoDesactivar(null)}>Cancelar</Button>
              <Button className="bg-[#1E5C8E] hover:bg-[#164a70]" onClick={() => dialogoDesactivar && handleDesactivarUsuario(dialogoDesactivar)}>
                <UserX className="h-4 w-4 mr-2" /> Desactivar
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
