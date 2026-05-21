// ============================================
// Hook: useVentas
// Gestiona el formulario de venta de planes
// ============================================

import { useState, useEffect, useCallback } from "react";
import { supabase } from "@/lib/supabase";

export interface Cliente {
  id: string;
  email: string;
  nombre_completo: string;
  rol: string;
}

export interface PlanBase {
  id: string;
  tipo: string;
  nombre: string;
  descripcion: string;
  precio_base: number;
  moneda: string;
  periodicidad: string;
}

export interface PlanConfig {
  id: string;
  pais_id: string;
  plan_base_id: string;
  precio_local: number;
  comision_aplicada: number;
  descuento_porcentaje: number;
  precio_anual: number;
  activo: boolean;
}

export interface Pais {
  id: string;
  nombre: string;
  codigo: string;
  moneda_local: string;
}

export interface Venta {
  id: string;
  medico_id: string;
  plan_config_id: string;
  fecha_inicio: string;
  fecha_fin: string;
  tipo_ciclo: string;
  precio_aplicado: number;
  moneda: string;
  estado: string;
  created_at: string;
}

export function useVentas() {
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [planesBase, setPlanesBase] = useState<PlanBase[]>([]);
  const [planesConfig, setPlanesConfig] = useState<PlanConfig[]>([]);
  const [paises, setPaises] = useState<Pais[]>([]);
  const [ventas, setVentas] = useState<Venta[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);

  // Cargar datos iniciales
  const cargarDatos = useCallback(async () => {
    setLoading(true);
    try {
           // Clientes (todos los perfiles activos)
      const { data: clientesData } = await supabase
        .from("perfiles")
        .select("id, email, nombre_completo, rol")
        .eq("activo", true)
        .order("nombre_completo");

      // Planes base activos
      const { data: planesData } = await supabase
        .from("planes_base")
        .select("*")
        .eq("activo", true)
        .order("nombre");

      // Países
      const { data: paisesData } = await supabase
        .from("configuracion_pais")
        .select("*")
        .eq("activo", true)
        .order("nombre");

      // Ventas recientes
      const { data: ventasData } = await supabase
        .from("planes_asignaciones")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(20);

      setClientes(clientesData || []);
      setPlanesBase(planesData || []);
      setPaises(paisesData || []);
      setVentas(ventasData || []);
    } catch (err) {
      console.error("Error cargando datos:", err);
    } finally {
      setLoading(false);
    }
  }, []);

   // Cargar configuraciones por país y plan
  const cargarConfiguraciones = useCallback(async (paisId: string, planBaseId: string) => {
    console.log("Buscando configuraciones:", { paisId, planBaseId });
    try {
      const { data, error } = await supabase
        .from("planes_configuracion")
        .select("*")
        .eq("pais_id", paisId)
        .eq("plan_base_id", planBaseId)
        .eq("activo", true);

      if (error) {
        console.error("Error SQL:", error);
        return;
      }

      console.log("Configuraciones encontradas:", data?.length || 0, data);
      setPlanesConfig(data || []);
    } catch (err) {
      console.error("Error cargando configuraciones:", err);
    }
  }, []);

  // Registrar venta
  const registrarVenta = useCallback(async (ventaData: {
    medico_id: string;
    plan_config_id: string;
    fecha_inicio: string;
    fecha_fin: string;
    tipo_ciclo: string;
    precio_aplicado: number;
    moneda: string;
  }) => {
    setSaving(true);
    try {
      // 1. Guardar en planes_asignaciones
      const { data, error } = await supabase
        .from("planes_asignaciones")
        .insert({
          ...ventaData,
          estado: "activo",
        })
        .select()
        .single();

      if (error) throw error;

           // 2. Notificar admin - usando la sesión del usuario actual
      try {
        const { data: sessionData } = await supabase.auth.getSession();
        const accessToken = sessionData.session?.access_token;
        const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || "https://fqnsmvkxsuujahhmpzuk.supabase.co";
        if (accessToken) {
          await fetch(`${supabaseUrl}/functions/v1/notificar-admin`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${accessToken}`, // Usar token del usuario, no service role
            },
            body: JSON.stringify({
              tipo: "venta",
              titulo: "Nueva venta de plan completada",
              mensaje: `Plan vendido a cliente ${ventaData.medico_id} por ${ventaData.precio_aplicado} ${ventaData.moneda}`,
              metadata: {
                venta_id: data.id,
                medico_id: ventaData.medico_id,
                plan_config_id: ventaData.plan_config_id,
                precio: ventaData.precio_aplicado,
                moneda: ventaData.moneda,
              },
              accion_url: "/admin-ezpay/ventas",
            }),
          });
        }
      } catch (notifError) {
        console.warn("Error notificando (no crítico):", notifError);
      }

      // 3. Actualizar lista
      setVentas((prev) => [data, ...prev]);
      return { success: true, data };
    } catch (err: any) {
      return { success: false, error: err.message };
    } finally {
      setSaving(false);
    }
  }, []);

  useEffect(() => {
    cargarDatos();
  }, [cargarDatos]);

  return {
    clientes,
    planesBase,
    planesConfig,
    paises,
    ventas,
    loading,
    saving,
    cargarConfiguraciones,
    registrarVenta,
    recargar: cargarDatos,
  };
}