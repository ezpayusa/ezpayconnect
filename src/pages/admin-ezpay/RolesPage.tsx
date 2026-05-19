import { useState, useEffect } from "react";
import { useRoles, type NuevoEmpleado } from "@/hooks/useRoles";
import { useAuth } from "@/hooks/useAuth";
import { useAuditoria } from "@/hooks/useAuditoria";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
  DialogClose,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Plus, UserPlus, Shield, Users, ToggleLeft, ToggleRight } from "lucide-react";

export default function RolesPage() {
  const { user } = useAuth();
  const { registrarLog } = useAuditoria();
  const {
    roles,
    empleados,
    loading,
    creating,
    fetchRoles,
    fetchEmpleados,
    crearEmpleado,
    toggleEmpleadoActivo,
    actualizarRolEmpleado,
  } = useRoles();

  const [isOpen, setIsOpen] = useState(false);
  const [nuevoEmpleado, setNuevoEmpleado] = useState<NuevoEmpleado>({
    email: "",
    password: "",
    nombre_completo: "",
    nombre: "",
    rol_id: "",
  });

  useEffect(() => {
    fetchRoles();
    fetchEmpleados();
  }, [fetchRoles, fetchEmpleados]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!nuevoEmpleado.email || !nuevoEmpleado.password || !nuevoEmpleado.rol_id) {
      alert("Email, contraseña y rol son obligatorios");
      return;
    }

    try {
      const result = await crearEmpleado(nuevoEmpleado, user?.id);

      // REGISTRAR EN AUDITORÍA
      const rolNombre = roles.find(r => r.id === nuevoEmpleado.rol_id)?.nombre || "desconocido";
      await registrarLog({
        accion: "crear_empleado",
        entidad: "empleado",
        detalle: { 
          email: nuevoEmpleado.email, 
          rol: rolNombre, 
          nombre: nuevoEmpleado.nombre_completo || nuevoEmpleado.nombre || "Sin nombre" 
        },
      });

      setIsOpen(false);
      setNuevoEmpleado({
        email: "",
        password: "",
        nombre_completo: "",
        nombre: "",
        rol_id: "",
      });
      alert("✅ Empleado creado exitosamente");
    } catch (error: any) {
      alert("❌ Error al crear empleado: " + (error.message || "Error desconocido"));
    }
  };

  const handleToggleActivo = async (id: string, activo: boolean) => {
    try {
      const empleado = empleados.find(e => e.id === id);
      await toggleEmpleadoActivo(id, activo);

      // REGISTRAR EN AUDITORÍA
      await registrarLog({
        accion: activo ? "activar" : "desactivar",
        entidad: "empleado",
        entidad_id: id,
        detalle: { 
          email: empleado?.email || "desconocido", 
          estado_anterior: !activo, 
          estado_nuevo: activo 
        },
      });

      alert(activo ? "✅ Empleado activado" : "✅ Empleado desactivado");
    } catch (error: any) {
      alert("❌ Error: " + error.message);
    }
  };

  const handleActualizarRol = async (userId: string, nuevoRolId: string) => {
    try {
      const empleado = empleados.find(e => e.id === userId);
      const rolAnterior = empleado?.rol || "desconocido";
      const rolNuevo = roles.find(r => r.id === nuevoRolId)?.nombre || "desconocido";

      await actualizarRolEmpleado(userId, nuevoRolId);

      // REGISTRAR EN AUDITORÍA
      await registrarLog({
        accion: "cambiar_rol",
        entidad: "empleado",
        entidad_id: userId,
        detalle: { 
          email: empleado?.email || "desconocido", 
          rol_anterior: rolAnterior, 
          rol_nuevo: rolNuevo 
        },
      });

      alert("✅ Rol actualizado");
    } catch (error: any) {
      alert("❌ Error: " + error.message);
    }
  };

  const getRolBadgeColor = (rol: string) => {
    switch (rol?.toLowerCase()) {
      case "admin":
      case "administrador":
        return "bg-red-500/10 text-red-500 border-red-500/20";
      case "medico":
      case "doctor":
        return "bg-blue-500/10 text-blue-500 border-blue-500/20";
      case "enfermera":
      case "enfermero":
        return "bg-green-500/10 text-green-500 border-green-500/20";
      case "recepcionista":
        return "bg-yellow-500/10 text-yellow-500 border-yellow-500/20";
      default:
        return "bg-gray-500/10 text-gray-500 border-gray-500/20";
    }
  };

  return (
    <div className="space-y-6 p-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-white">Gestión de Roles y Empleados</h1>
          <p className="text-gray-400 mt-1">
            Administra los roles del sistema y los empleados de tu organización
          </p>
        </div>
        <Dialog open={isOpen} onOpenChange={setIsOpen}>
          <DialogTrigger asChild>
            <Button className="bg-[#00f2ff] text-black hover:bg-[#00f2ff]/90 font-semibold">
              <UserPlus className="w-4 h-4 mr-2" />
              Nuevo Empleado
            </Button>
          </DialogTrigger>
          <DialogContent className="bg-[#0a0a0a] border-gray-800 text-white max-w-md">
            <DialogHeader>
              <DialogTitle className="text-xl text-white flex items-center gap-2">
                <Plus className="w-5 h-5 text-[#00f2ff]" />
                Crear Nuevo Empleado
              </DialogTitle>
              <DialogDescription className="text-gray-400">
                El empleado recibirá un email con sus credenciales de acceso.
              </DialogDescription>
            </DialogHeader>

            <form onSubmit={handleSubmit} className="space-y-4 mt-4">
              <div className="space-y-2">
                <Label htmlFor="email" className="text-gray-300">
                  Email <span className="text-red-400">*</span>
                </Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="empleado@ezpayconnect.com"
                  value={nuevoEmpleado.email}
                  onChange={(e) =>
                    setNuevoEmpleado({ ...nuevoEmpleado, email: e.target.value })
                  }
                  className="bg-[#1a1a1a] border-gray-700 text-white placeholder:text-gray-600"
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="password" className="text-gray-300">
                  Contraseña <span className="text-red-400">*</span>
                </Label>
                <Input
                  id="password"
                  type="password"
                  placeholder="Mínimo 6 caracteres"
                  value={nuevoEmpleado.password}
                  onChange={(e) =>
                    setNuevoEmpleado({ ...nuevoEmpleado, password: e.target.value })
                  }
                  className="bg-[#1a1a1a] border-gray-700 text-white placeholder:text-gray-600"
                  required
                  minLength={6}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="nombre_completo" className="text-gray-300">
                  Nombre Completo
                </Label>
                <Input
                  id="nombre_completo"
                  placeholder="Juan Pérez"
                  value={nuevoEmpleado.nombre_completo}
                  onChange={(e) =>
                    setNuevoEmpleado({ ...nuevoEmpleado, nombre_completo: e.target.value })
                  }
                  className="bg-[#1a1a1a] border-gray-700 text-white placeholder:text-gray-600"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="rol" className="text-gray-300">
                  Rol <span className="text-red-400">*</span>
                </Label>
                <Select
                  value={nuevoEmpleado.rol_id}
                  onValueChange={(value) =>
                    setNuevoEmpleado({ ...nuevoEmpleado, rol_id: value })
                  }
                >
                  <SelectTrigger className="bg-[#1a1a1a] border-gray-700 text-white">
                    <SelectValue placeholder="Selecciona un rol" />
                  </SelectTrigger>
                  <SelectContent className="bg-[#1a1a1a] border-gray-700">
                    {roles.map((rol) => (
                      <SelectItem
                        key={rol.id}
                        value={rol.id}
                        className="text-white hover:bg-gray-800 focus:bg-gray-800"
                      >
                        <div className="flex items-center gap-2">
                          <Shield className="w-4 h-4 text-[#00f2ff]" />
                          {rol.nombre}
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <DialogFooter className="mt-6">
                <DialogClose asChild>
                  <Button
                    type="button"
                    variant="outline"
                    className="border-gray-700 text-gray-300 hover:bg-gray-800"
                  >
                    Cancelar
                  </Button>
                </DialogClose>
                <Button
                  type="submit"
                  disabled={creating}
                  className="bg-[#00f2ff] text-black hover:bg-[#00f2ff]/90 font-semibold"
                >
                  {creating ? "Creando..." : "Crear Empleado"}
                </Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="bg-[#0f0f0f] border-gray-800">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-gray-400 flex items-center gap-2">
              <Shield className="w-4 h-4 text-[#00f2ff]" />
              Total Roles
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-white">{roles.length}</p>
          </CardContent>
        </Card>
        <Card className="bg-[#0f0f0f] border-gray-800">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-gray-400 flex items-center gap-2">
              <Users className="w-4 h-4 text-[#00f2ff]" />
              Total Empleados
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-white">{empleados.length}</p>
          </CardContent>
        </Card>
        <Card className="bg-[#0f0f0f] border-gray-800">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-gray-400 flex items-center gap-2">
              <ToggleRight className="w-4 h-4 text-green-400" />
              Empleados Activos
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-green-400">
              {empleados.filter((e) => e.activo).length}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Tabla de Empleados */}
      <Card className="bg-[#0f0f0f] border-gray-800">
        <CardHeader>
          <CardTitle className="text-white flex items-center gap-2">
            <Users className="w-5 h-5 text-[#00f2ff]" />
            Empleados
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="text-center py-8 text-gray-500">Cargando empleados...</div>
          ) : empleados.length === 0 ? (
            <div className="text-center py-8 text-gray-500">
              No hay empleados registrados. Crea el primero con el botón "Nuevo Empleado".
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="border-gray-800 hover:bg-transparent">
                  <TableHead className="text-gray-400">Nombre</TableHead>
                  <TableHead className="text-gray-400">Email</TableHead>
                  <TableHead className="text-gray-400">Rol</TableHead>
                  <TableHead className="text-gray-400">Estado</TableHead>
                  <TableHead className="text-gray-400 text-right">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {empleados.map((empleado) => (
                  <TableRow
                    key={empleado.id}
                    className="border-gray-800 hover:bg-[#1a1a1a]"
                  >
                    <TableCell className="text-white font-medium">
                      {empleado.nombre_completo || empleado.nombre || "Sin nombre"}
                    </TableCell>
                    <TableCell className="text-gray-400">{empleado.email}</TableCell>
                    <TableCell>
                      <Badge
                        variant="outline"
                        className={getRolBadgeColor(empleado.rol)}
                      >
                        {empleado.rol || "Sin rol"}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <Badge
                        variant="outline"
                        className={
                          empleado.activo
                            ? "bg-green-500/10 text-green-500 border-green-500/20"
                            : "bg-red-500/10 text-red-500 border-red-500/20"
                        }
                      >
                        {empleado.activo ? "Activo" : "Inactivo"}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex items-center justify-end gap-2">
                        {/* Cambiar Rol */}
                        <Select
                          value={empleado.rol_id || ""}
                          onValueChange={(value) =>
                            handleActualizarRol(empleado.id, value)
                          }
                        >
                          <SelectTrigger className="w-[140px] bg-[#1a1a1a] border-gray-700 text-white text-xs h-8">
                            <SelectValue placeholder="Cambiar rol" />
                          </SelectTrigger>
                          <SelectContent className="bg-[#1a1a1a] border-gray-700">
                            {roles.map((rol) => (
                              <SelectItem
                                key={rol.id}
                                value={rol.id}
                                className="text-white hover:bg-gray-800 text-xs"
                              >
                                {rol.nombre}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>

                        {/* Activar/Desactivar */}
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() =>
                            handleToggleActivo(empleado.id, !empleado.activo)
                          }
                          className={
                            empleado.activo
                              ? "text-red-400 hover:text-red-300 hover:bg-red-500/10"
                              : "text-green-400 hover:text-green-300 hover:bg-green-500/10"
                          }
                        >
                          {empleado.activo ? (
                            <ToggleLeft className="w-4 h-4" />
                          ) : (
                            <ToggleRight className="w-4 h-4" />
                          )}
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Tabla de Roles del Sistema */}
      <Card className="bg-[#0f0f0f] border-gray-800">
        <CardHeader>
          <CardTitle className="text-white flex items-center gap-2">
            <Shield className="w-5 h-5 text-[#00f2ff]" />
            Roles del Sistema
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="text-center py-8 text-gray-500">Cargando roles...</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="border-gray-800 hover:bg-transparent">
                  <TableHead className="text-gray-400">Nombre</TableHead>
                  <TableHead className="text-gray-400">Descripción</TableHead>
                  <TableHead className="text-gray-400">Permisos</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {roles.map((rol) => (
                  <TableRow
                    key={rol.id}
                    className="border-gray-800 hover:bg-[#1a1a1a]"
                  >
                    <TableCell className="text-white font-medium">
                      <div className="flex items-center gap-2">
                        <Shield className="w-4 h-4 text-[#00f2ff]" />
                        {rol.nombre}
                      </div>
                    </TableCell>
                    <TableCell className="text-gray-400">
                      {rol.descripcion || "Sin descripción"}
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {(rol.permisos || []).map((permiso: string) => (
                          <Badge
                            key={permiso}
                            variant="outline"
                            className="bg-[#00f2ff]/10 text-[#00f2ff] border-[#00f2ff]/20 text-xs"
                          >
                            {permiso}
                          </Badge>
                        ))}
                        {(rol.permisos || []).length === 0 && (
                          <span className="text-gray-600 text-sm">Sin permisos definidos</span>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
