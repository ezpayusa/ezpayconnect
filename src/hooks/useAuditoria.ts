import { useState, useCallback } from "react";
import { supabase } from "@/lib/supabase";
const SUPABASE_URL = "https://fqnsmvkxsuujahhmpzuk.supabase.co";
const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZxbnNtdmt4c3V1amFoaG1wenVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE1ODU5NjQsImV4cCI6MjA1NzE2MTk2NH0.5_8_ZH_1X4zYX_qXz7ZzZzZzZzZzZzZzZzZzZzZzZz";

export interface AuditoriaLog {
  id: string;
  usuario_id: string | null;
  usuario_email: string;
  usuario_nombre: string;
  accion: string;
  entidad: string;
  entidad_id: string | null;
  detalle: any;
  ip_address: string | null;
  user_agent: string | null;
  created_at: string;
}

export function useAuditoria() {
  const [logs, setLogs] = useState<AuditoriaLog[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const registrarLog = useCallback(
    async (data: {
      accion: string;
      entidad: string;
      entidad_id?: string;
      detalle?: any;
    }) => {
      try {
        const { data: sessionData } = await supabase.auth.getSession();
        const user = sessionData.session?.user;

        const payload = {
          usuario_id: user?.id || null,
          usuario_email: user?.email || "sistema",
          usuario_nombre: user?.user_metadata?.nombre || user?.email || "sistema",
          accion: data.accion,
          entidad: data.entidad,
          entidad_id: data.entidad_id || null,
          detalle: data.detalle || {},
          ip_address: null,
          user_agent: navigator.userAgent,
        };

        const response = await fetch(
          `${SUPABASE_URL}/functions/v1/registrar-auditoria`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${ANON_KEY}`,
            },
            body: JSON.stringify(payload),
          }
        );

        const result = await response.json();
        if (!response.ok) throw new Error(result.error || "Error al registrar log");
        return result;
      } catch (err: any) {
        console.error("Error registrando auditoria:", err);
        return null;
      }
    },
    []
  );

  const listarLogs = useCallback(
    async (filtros?: {
      accion?: string;
      entidad?: string;
      usuario_email?: string;
      fechaDesde?: string;
      fechaHasta?: string;
      limite?: number;
    }) => {
      setLoading(true);
      setError(null);
      try {
        let query = supabase
          .from("auditoria_logs")
          .select("*")
          .order("created_at", { ascending: false });

        if (filtros?.accion) query = query.eq("accion", filtros.accion);
        if (filtros?.entidad) query = query.eq("entidad", filtros.entidad);
        if (filtros?.usuario_email) query = query.ilike("usuario_email", `%${filtros.usuario_email}%`);
        if (filtros?.fechaDesde) query = query.gte("created_at", filtros.fechaDesde);
        if (filtros?.fechaHasta) query = query.lte("created_at", filtros.fechaHasta);
        if (filtros?.limite) query = query.limit(filtros.limite);

        const { data, error: err } = await query;
        if (err) throw err;

        setLogs(data || []);
        return data || [];
      } catch (err: any) {
        setError(err.message);
        return [];
      } finally {
        setLoading(false);
      }
    },
    []
  );

  return {
    logs,
    loading,
    error,
    registrarLog,
    listarLogs,
  };
}
