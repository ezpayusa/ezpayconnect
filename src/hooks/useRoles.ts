import { useState, useCallback } from "react";
import { supabase } from "@/lib/supabase";

export interface Rol {
  id: string;
  nombre: string;
  descripcion: string | null;
  permisos: string[];
  created_at: string;
}

export interface Empleado {
  id: string;
  email: string;
  nombre_completo: string | null;
  nombre: string | null;
  rol: string;
  rol_id: string | null;
  activo: boolean;
  created_at: string;
}

export interface NuevoEmpleado {
  email: string;
  password: string;
  nombre_completo?: string;
  nombre?: string;
  rol_id: string;
}

export function useRoles() {
  const [roles, setRoles] = useState<Rol[]>([]);
  const [empleados, setEmpleados] = useState<Empleado[]>([]);
  const [loading, setLoading] = useState(false);
  const [creating, setCreating] = useState(false);

  // Obtener todos los roles (directo, no tiene problema RLS)
  const fetchRoles = useCallback(async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from("roles")
        .select("*")
        .order("nombre");

      if (error) throw error;
      setRoles(data || []);
    } catch (error: any) {
      alert("Error: " + (error.message || "No se pudieron cargar los roles"));
    } finally {
      setLoading(false);
    }
  }, []);

  // Obtener empleados usando Edge Function (ignora RLS)
  const fetchEmpleados = useCallback(async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke("listar-empleados", {
        body: {},
      });

      if (error) {
        console.error("Error en Edge Function:", error?.message ?? error?.code);
        throw new Error(error.message || "Error al cargar empleados");
      }

      if (!data?.success) {
        throw new Error(data?.error || "Error desconocido");
      }

      setEmpleados(data.data || []);
    } catch (error: any) {
      alert("Error: " + (error.message || "No se pudieron cargar los empleados"));
    } finally {
      setLoading(false);
    }
  }, []);

  // Crear empleado usando Edge Function
  const crearEmpleado = useCallback(async (
    empleado: NuevoEmpleado,
    adminUserId?: string
  ) => {
    setCreating(true);
    try {
      const { data, error } = await supabase.functions.invoke("crear-empleado", {
        body: {
          email: empleado.email,
          password: empleado.password,
          nombre_completo: empleado.nombre_completo,
          nombre: empleado.nombre,
          rol_id: empleado.rol_id,
          asignado_por: adminUserId,
        },
      });

      if (error) {
        console.error("Error en Edge Function:", error?.message ?? error?.code);
        throw new Error(error.message || "Error al crear empleado");
      }

      if (!data?.success) {
        throw new Error(data?.error || "Error desconocido al crear empleado");
      }

      alert("✅ Empleado creado: " + data.data.nombre_completo + " con rol " + data.data.rol);

      // Recargar lista de empleados
      await fetchEmpleados();

      return data.data;
    } catch (error: any) {
      alert("❌ Error al crear empleado: " + (error.message || "No se pudo crear el empleado"));
      throw error;
    } finally {
      setCreating(false);
    }
  }, [fetchEmpleados]);

  // Activar/desactivar empleado
  const toggleEmpleadoActivo = useCallback(async (id: string, activo: boolean) => {
    try {
      const { error } = await supabase
        .from("perfiles")
        .update({ activo })
        .eq("id", id);

      if (error) throw error;

      await fetchEmpleados();
    } catch (error: any) {
      alert("Error: " + error.message);
    }
  }, [fetchEmpleados]);

  // Actualizar rol de empleado
  const actualizarRolEmpleado = useCallback(async (userId: string, nuevoRolId: string) => {
    try {
      const { data: rolData } = await supabase
        .from("roles")
        .select("nombre")
        .eq("id", nuevoRolId)
        .single();

      const { error: perfilError } = await supabase
        .from("perfiles")
        .update({ rol_id: nuevoRolId, rol: rolData?.nombre })
        .eq("id", userId);

      if (perfilError) throw perfilError;

      const { error: usuarioRolError } = await supabase
        .from("usuario_roles")
        .update({ rol_id: nuevoRolId })
        .eq("usuario_id", userId);

      if (usuarioRolError) throw usuarioRolError;

      await fetchEmpleados();
    } catch (error: any) {
      alert("Error: " + error.message);
    }
  }, [fetchEmpleados]);

  return {
    roles,
    empleados,
    loading,
    creating,
    fetchRoles,
    fetchEmpleados,
    crearEmpleado,
    toggleEmpleadoActivo,
    actualizarRolEmpleado,
  };
}
