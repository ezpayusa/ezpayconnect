import { useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import type { ProductoEmpresa } from '@/proveedor/types/proveedor.types';

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
  // Proveedores
  resultadosProveedores: ProductoEmpresa[];
  buscarEnProveedores: (query: string) => Promise<void>;
  // General
  loading: boolean;
  buscar: (query: string) => Promise<void>;
  buscarPorFarmacia: (farmaciaId: number) => Promise<void>;
}

export function useBusquedaMedicamentos(): UseBusquedaMedicamentosReturn {
  const [resultadosFarmacias, setResultadosFarmacias] = useState<FarmaciaMedicamento[]>([]);
  const [resultadosLaboratorios, setResultadosLaboratorios] = useState<FarmaciaMedicamento[]>([]);
  const [resultadosProveedores, setResultadosProveedores] = useState<ProductoEmpresa[]>([]);
  const [resultados, setResultados] = useState<FarmaciaMedicamento[]>([]);
  const [loading, setLoading] = useState(false);

  // ─── Búsqueda general (sin filtro de tipo, para compatibilidad) ───
  const buscar = useCallback(async (query: string) => {
    if (!query.trim()) {
      setResultados([]);
      setResultadosProveedores([]);
      return;
    }
    setLoading(true);
    try {
      // Buscar en farmacias
      const { data: farmaciaData, error: farmaciaError } = await supabase
        .from('farmacia_medicamentos')
        .select(`
          *,
          farmacia:farmacia_id(id, nombre, direccion, telefono, email, encargado, horario, tipo)
        `)
        .ilike('nombre_medicamento', `%${query.trim()}%`)
        .gt('stock_actual', 0)
        .order('precio_unitario', { ascending: true });

      if (farmaciaError) throw farmaciaError;
      setResultados(farmaciaData || []);

      // Buscar en proveedores
      const { data: proveedorData, error: proveedorError } = await supabase
        .from('productos_empresa')
        .select('*, empresa:empresa_id(nombre_empresa, tipo)')
        .ilike('nombre_producto', `%${query.trim()}%`)
        .eq('estado', 'activo')
        .order('precio_unitario', { ascending: true });

      if (proveedorError) throw proveedorError;
      // Defensa en profundidad: excluir productos de empresas afines de la búsqueda
      // del médico (la RLS ya los excluye en servidor; esto cubre cualquier camino).
      const sinAfines = (proveedorData || []).filter((p: any) => p.empresa?.tipo !== 'empresa_afin');
      setResultadosProveedores(sinAfines as ProductoEmpresa[]);
    } catch (err: any) {
      console.error('Error buscando medicamentos:', err);
      toast.error('Error al buscar medicamentos', { description: err.message });
      setResultados([]);
      setResultadosProveedores([]);
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

  // ─── Búsqueda en proveedores ───
  const buscarEnProveedores = useCallback(async (query: string) => {
    if (!query.trim()) {
      setResultadosProveedores([]);
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('productos_empresa')
        .select('*, empresa:empresa_id(nombre_empresa, tipo)')
        .ilike('nombre_producto', `%${query.trim()}%`)
        .eq('estado', 'activo')
        .order('precio_unitario', { ascending: true });

      if (error) throw error;
      // Defensa en profundidad: excluir empresas afines (la RLS ya las excluye en servidor).
      const sinAfines = (data || []).filter((p: any) => p.empresa?.tipo !== 'empresa_afin');
      setResultadosProveedores(sinAfines as ProductoEmpresa[]);
    } catch (err: any) {
      console.error('Error buscando en proveedores:', err);
      toast.error('Error al buscar proveedores', { description: err.message });
      setResultadosProveedores([]);
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
    resultadosProveedores,
    buscarEnProveedores,
  };
}
