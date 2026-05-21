// ============================================
// Hook: useNotificacionesAdmin
// Notificaciones exclusivas del panel admin EZPay
// Con soporte para estados: pendiente, en_proceso, completada
// ============================================

import { useState, useCallback } from "react";
import { supabase } from "@/lib/supabase";

export interface NotificacionAdmin {
  id: string;
  usuario_id: string;
  tipo: string;
  titulo: string;
  mensaje: string;
  estado: "pendiente" | "en_proceso" | "completada" | "archivada";
  leida: boolean;
  accion_url: string | null;
  metadata: any;
  evento_id: string;
  rol_destinatario: string;
  nivel_destinatario: number;
  created_at: string;
}

// Tipos de notificación exclusivos del panel admin
const TIPOS_ADMIN = ["empleado", "venta", "plan", "reporte"];

export function useNotificacionesAdmin() {
  const [notificaciones, setNotificaciones] = useState<NotificacionAdmin[]>([]);
  const [noLeidas, setNoLeidas] = useState(0);
  const [pendientes, setPendientes] = useState(0);
  const [loading, setLoading] = useState(false);

  // Listar notificaciones del usuario actual (solo admin)
  const listarNotificaciones = useCallback(async () => {
    setLoading(true);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const userId = sessionData.session?.user?.id;
      if (!userId) {
        setNotificaciones([]);
        setNoLeidas(0);
        setPendientes(0);
        return [];
      }

      const { data, error } = await supabase
        .from("notificaciones")
        .select("*")
        .eq("usuario_id", userId)
        .in("tipo", TIPOS_ADMIN)
        .in("estado", ["pendiente", "en_proceso", "completada"])
        .order("created_at", { ascending: false })
        .limit(50);

      if (error) throw error;

      const notifs = (data || []) as NotificacionAdmin[];
      setNotificaciones(notifs);
      setNoLeidas(notifs.filter((n) => !n.leida).length);
      setPendientes(notifs.filter((n) => n.estado === "pendiente").length);
      return notifs;
    } catch (err: any) {
      console.error("Error listando notificaciones admin:", err);
      return [];
    } finally {
      setLoading(false);
    }
  }, []);

  // Marcar como leída
  const marcarLeida = useCallback(async (id: string) => {
    try {
      const { error } = await supabase
        .from("notificaciones")
        .update({ leida: true })
        .eq("id", id);

      if (error) throw error;

      setNotificaciones((prev) =>
        prev.map((n) => (n.id === id ? { ...n, leida: true } : n))
      );
      setNoLeidas((prev) => Math.max(0, prev - 1));
    } catch (err: any) {
      console.error("Error marcando notificacion como leida:", err);
    }
  }, []);

  // Marcar como EN PROCESO (solo rol directo)
  const marcarEnProceso = useCallback(async (id: string) => {
    try {
      const { error } = await supabase
        .from("notificaciones")
        .update({ estado: "en_proceso", leida: true })
        .eq("id", id);

      if (error) throw error;

      setNotificaciones((prev) =>
        prev.map((n) =>
          n.id === id ? { ...n, estado: "en_proceso", leida: true } : n
        )
      );
      setNoLeidas((prev) => Math.max(0, prev - 1));
      setPendientes((prev) => Math.max(0, prev - 1));
    } catch (err: any) {
      console.error("Error marcando en proceso:", err);
    }
  }, []);

  // Marcar como COMPLETADA
  const marcarCompletada = useCallback(async (id: string, evento_id: string) => {
    try {
      // Actualizar la notificación del rol directo
      const { error } = await supabase
        .from("notificaciones")
        .update({ estado: "completada", leida: true })
        .eq("id", id);

      if (error) throw error;

      // Archivar notificaciones de seguimiento del mismo evento
      const { error: errArchivar } = await supabase
        .from("notificaciones")
        .update({ estado: "archivada", leida: true })
        .eq("evento_id", evento_id)
        .eq("metadata->es_seguimiento", true);

      if (errArchivar) console.warn("Error archivando seguimientos:", errArchivar);

      setNotificaciones((prev) =>
        prev.map((n) =>
          n.id === id
            ? { ...n, estado: "completada", leida: true }
            : n.evento_id === evento_id && n.metadata?.es_seguimiento
            ? { ...n, estado: "archivada", leida: true }
            : n
        )
      );
      setNoLeidas((prev) => Math.max(0, prev - 1));
      setPendientes((prev) => Math.max(0, prev - 1));
    } catch (err: any) {
      console.error("Error marcando completada:", err);
    }
  }, []);

  // Marcar todas como leídas (solo las del usuario actual)
  const marcarTodasLeidas = useCallback(async () => {
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const userId = sessionData.session?.user?.id;
      if (!userId) return;

      const { error } = await supabase
        .from("notificaciones")
        .update({ leida: true })
        .eq("usuario_id", userId)
        .eq("leida", false)
        .in("tipo", TIPOS_ADMIN);

      if (error) throw error;

      setNotificaciones((prev) => prev.map((n) => ({ ...n, leida: true })));
      setNoLeidas(0);
    } catch (err: any) {
      console.error("Error marcando todas como leidas:", err);
    }
  }, []);

  return {
    notificaciones,
    noLeidas,
    pendientes,
    loading,
    listarNotificaciones,
    marcarLeida,
    marcarEnProceso,
    marcarCompletada,
    marcarTodasLeidas,
  };
}