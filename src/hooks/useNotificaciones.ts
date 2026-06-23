import { useState, useCallback } from "react";
import { supabase } from "@/lib/supabase";

export interface Notificacion {
  id: string;
  usuario_id: string | null;
  tipo: string;
  titulo: string;
  mensaje: string;
  leida: boolean;
  accion_url: string | null;
  metadata: any;
  created_at: string;
}

export function useNotificaciones() {
  const [notificaciones, setNotificaciones] = useState<Notificacion[]>([]);
  const [noLeidas, setNoLeidas] = useState(0);
  const [loading, setLoading] = useState(false);

  // Listar notificaciones del usuario actual
  const listarNotificaciones = useCallback(async () => {
    setLoading(true);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const userId = sessionData.session?.user?.id;

      let query = supabase
        .from("notificaciones")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(50);

      if (userId) {
        query = query.eq("usuario_id", userId);
      }

      const { data, error } = await query;

      if (error) throw error;

      setNotificaciones(data || []);
      setNoLeidas((data || []).filter((n) => !n.leida).length);
      return data || [];
    } catch (err: any) {
      console.error("Error listando notificaciones:", err);
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

  // Marcar todas como leídas
  const marcarTodasLeidas = useCallback(async () => {
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const userId = sessionData.session?.user?.id;
      if (!userId) return;

      const { error } = await supabase
        .from("notificaciones")
        .update({ leida: true })
        .eq("usuario_id", userId)
        .eq("leida", false);

      if (error) throw error;

      setNotificaciones((prev) => prev.map((n) => ({ ...n, leida: true })));
      setNoLeidas(0);
    } catch (err: any) {
      console.error("Error marcando todas como leidas:", err);
    }
  }, []);

  // crearNotificacion eliminado (CIERRE FINAL push-tx, bloque 3): helper muerto que hacía fetch a la edge
  // enviar-notificacion (ahora stub-410). Las notifs in-app se crean por RPCs DEFINER gateados.

  return {
    notificaciones,
    noLeidas,
    loading,
    listarNotificaciones,
    marcarLeida,
    marcarTodasLeidas,
  };
}