import { useState, useCallback } from "react";
import { supabase } from "@/lib/supabase";

const SUPABASE_URL = "https://fqnsmvkxsuujahhmpzuk.supabase.co";
const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZxbnNtdmt4c3V1amFoaG1wenVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE1ODU5NjQsImV4cCI6MjA1NzE2MTk2NH0.5_8_ZH_1X4zYX_qXz7ZzZzZzZzZzZzZzZzZzZzZzZz";

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
      const { data, error } = await supabase
        .from("notificaciones")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(50);

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

  // Crear notificación vía Edge Function
  const crearNotificacion = useCallback(
    async (data: {
      usuario_id?: string;
      tipo: string;
      titulo: string;
      mensaje: string;
      accion_url?: string;
      metadata?: any;
    }) => {
      try {
        const response = await fetch(
          `${SUPABASE_URL}/functions/v1/enviar-notificacion`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${ANON_KEY}`,
            },
            body: JSON.stringify(data),
          }
        );

        const result = await response.json();
        if (!response.ok) throw new Error(result.error || "Error al crear notificacion");
        return result;
      } catch (err: any) {
        console.error("Error creando notificacion:", err);
        return null;
      }
    },
    []
  );

  return {
    notificaciones,
    noLeidas,
    loading,
    listarNotificaciones,
    marcarLeida,
    marcarTodasLeidas,
    crearNotificacion,
  };
}