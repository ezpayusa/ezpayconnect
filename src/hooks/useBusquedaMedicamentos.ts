import { useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';

export interface FarmaciaMedicamento {
  id: string;
  farmacia_id: number;
  nombre_medicamento: string;
  descripcion: string;
  presentacion: string;
  stock_actual: number;
  stock_minimo: number;
  precio_unitario: number;
  laboratorio: string;
  lote: string | null;
  farmacia?: {
    id: number;
    nombre: string;
    direccion: string;
    telefono: string;
    email: string | null;
    encargado: string;
    horario: string;
    tipo?: string; // 'farmacia' | 'laboratorio'
  };
}

interface UseBusquedaMedicamentosReturn {
  // Farmacias
  resultadosFarmacias: FarmaciaMedicamento[];
  buscarEnFarmacias: (query: string) => Promise<void>;
  // Laboratorios
  resultadosLaboratorios: FarmaciaMedicamento[];
  buscarEnLaboratorios: (query: string) => Promise<void>;
  // General
  loading: boolean;
  buscar: (query: string) => Promise<void>;
  buscarPorFarmacia: (farmaciaId: number) => Promise<void>;
}

export function useBusquedaMedicamentos(): UseBusquedaMedicamentosReturn {
  const [resultadosFarmacias, setResultadosFarmacias] = useState<FarmaciaMedicamento[]>([]);
  const [resultadosLaboratorios, setResultadosLaboratorios] = useState<FarmaciaMedicamento[]>([]);
  const [resultados, setResultados] = useState<FarmaciaMedicamento[]>([]);
  const [loading, setLoading] = useState(false);

  // ─── Búsqueda general (sin filtro de tipo, para compatibilidad) ───
  const buscar = useCallback(async (query: string) => {
    if (!query.trim()) {
      setResultados([]);
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('farmacia_medicamentos')
        .select(`
          *,
          farmacia:farmacia_id(id, nombre, direccion, telefono, email, encargado, horario, tipo)
        `)
        .ilike('nombre_medicamento', `%${query.trim()}%`)
        .gt('stock_actual', 0)
        .order('precio_unitario', { ascending: true });
      if (error) throw error;
      setResultados(data || []);
    } catch (err: any) {
      console.error('Error buscando medicamentos:', err);
      toast.error('Error al buscar medicamentos', { description: err.message });
      setResultados([]);
    } finally {
      setLoading(false);
    }
  }, []);

  // ─── Búsqueda solo en FARMACIAS ───
  const buscarEnFarmacias = useCallback(async (query: string) => {
    if (!query.trim()) {
      setResultadosFarmacias([]);
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('farmacia_medicamentos')
        .select(`
          *,
          farmacia:farmacia_id!inner(id, nombre, direccion, telefono, email, encargado, horario, tipo)
        `)
        .ilike('nombre_medicamento', `%${query.trim()}%`)
        .gt('stock_actual', 0)
        .eq('farmacia.tipo', 'farmacia') // ← filtra solo farmacias
        .order('precio_unitario', { ascending: true });
      
      if (error) throw error;
      setResultadosFarmacias(data || []);
    } catch (err: any) {
      console.error('Error buscando en farmacias:', err);
      toast.error('Error al buscar farmacias', { description: err.message });
      setResultadosFarmacias([]);
    } finally {
      setLoading(false);
    }
  }, []);

  // ─── Búsqueda solo en LABORATORIOS ───
  const buscarEnLaboratorios = useCallback(async (query: string) => {
    if (!query.trim()) {
      setResultadosLaboratorios([]);
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('farmacia_medicamentos')
        .select(`
          *,
          farmacia:farmacia_id!inner(id, nombre, direccion, telefono, email, encargado, horario, tipo)
        `)
        .ilike('nombre_medicamento', `%${query.trim()}%`)
        .gt('stock_actual', 0)
        .eq('farmacia.tipo', 'laboratorio') // ← filtra solo laboratorios
        .order('precio_unitario', { ascending: true });
      
      if (error) throw error;
      setResultadosLaboratorios(data || []);
    } catch (err: any) {
      console.error('Error buscando en laboratorios:', err);
      toast.error('Error al buscar laboratorios', { description: err.message });
      setResultadosLaboratorios([]);
    } finally {
      setLoading(false);
    }
  }, []);

  // ─── Búsqueda por farmacia específica (compatibilidad) ───
  const buscarPorFarmacia = useCallback(async (farmaciaId: number) => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('farmacia_medicamentos')
        .select(`
          *,
          farmacia:farmacia_id(id, nombre, direccion, telefono, email, encargado, horario, tipo)
        `)
        .eq('farmacia_id', farmaciaId)
        .gt('stock_actual', 0)
        .order('nombre_medicamento', { ascending: true });
      if (error) throw error;
      setResultados(data || []);
    } catch (err: any) {
      console.error('Error cargando inventario:', err);
      toast.error('Error al cargar inventario', { description: err.message });
      setResultados([]);
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    resultados,
    loading,
    buscar,
    buscarPorFarmacia,
    resultadosFarmacias,
    buscarEnFarmacias,
    resultadosLaboratorios,
    buscarEnLaboratorios,
  };
}