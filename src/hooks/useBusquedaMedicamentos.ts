import { useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import type { ProductoEmpresa } from '@/proveedor/types/proveedor.types';

export interface FarmaciaMedicamento {
  id: string;
  farmacia_id: number;
  medicamento_id: number | null;
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
    empresa_id?: string | null;          // cadena (NULL = catálogo global, no ruteable)
    empresa?: { nombre_empresa: string } | null;  // nombre de la cadena
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
  resultados: FarmaciaMedicamento[];
  loading: boolean;
  // 3.3: filtro de ruteo ON por default (solo sucursales ruteables: empresa_id NOT NULL + activas).
  // incluirCatalogoGlobal=true es opt-out SOLO para discovery (BuscarMedicamentosPage).
  buscar: (query: string, incluirCatalogoGlobal?: boolean) => Promise<void>;
  // Camino MÉDICO: matchea por medicamento_id (FK al catálogo global), NO por texto.
  buscarPorMedicamento: (medicamentoId: number, incluirCatalogoGlobal?: boolean) => Promise<void>;
  buscarPorFarmacia: (farmaciaId: number) => Promise<void>;
}

export function useBusquedaMedicamentos(): UseBusquedaMedicamentosReturn {
  const [resultadosFarmacias, setResultadosFarmacias] = useState<FarmaciaMedicamento[]>([]);
  const [resultadosLaboratorios, setResultadosLaboratorios] = useState<FarmaciaMedicamento[]>([]);
  const [resultadosProveedores, setResultadosProveedores] = useState<ProductoEmpresa[]>([]);
  const [resultados, setResultados] = useState<FarmaciaMedicamento[]>([]);
  const [loading, setLoading] = useState(false);

  // ─── Búsqueda general ───
  // 3.3: por DEFAULT filtra a sucursales RUTEABLES (farmacia.empresa_id NOT NULL + activa), stackeado sobre
  // stock>0; NO toca el término país de la RLS farm_med_disp_medico. !inner = el filtro del embed EXCLUYE la
  // fila padre (no la nullea → el catálogo global no se cuela). incluirCatalogoGlobal=true (solo discovery) opt-out.
  const buscar = useCallback(async (query: string, incluirCatalogoGlobal = false) => {
    if (!query.trim()) {
      setResultados([]);
      setResultadosProveedores([]);
      return;
    }
    setLoading(true);
    try {
      // Buscar en farmacias. Embed con !inner + cadena (empresa_id → nombre_empresa) para agrupar por cadena.
      let q = supabase
        .from('farmacia_medicamentos')
        .select(`
          *,
          farmacia:farmacia_id!inner(id, nombre, direccion, telefono, email, encargado, horario, tipo, activo, empresa_id, empresa:empresa_id(nombre_empresa))
        `)
        .ilike('nombre_medicamento', `%${query.trim()}%`)
        .gt('stock_actual', 0);
      if (!incluirCatalogoGlobal) {
        // RUTEO: excluye catálogo global (empresa_id NULL) Y sucursales desactivadas (3.1). Sobre filas padre (!inner).
        q = q.not('farmacia.empresa_id', 'is', null).eq('farmacia.activo', true);
      }
      const { data: farmaciaData, error: farmaciaError } = await q.order('precio_unitario', { ascending: true });

      if (farmaciaError) throw farmaciaError;
      // 3.3-fix nombre-de-cadena: el médico no lee empresas_proveedoras (RLS) → el embed nombre_empresa viene
      // null. Enriquecer con un RPC DEFINER acotado que devuelve SOLO (farmacia_id, nombre_empresa) de las
      // farmacias ya visibles. Best-effort: si el RPC falla/no responde, queda el fallback (farmacia.nombre).
      let enriquecidos = (farmaciaData || []) as any[];
      const farmaciaIds = [...new Set(enriquecidos.map((r: any) => r.farmacia?.id).filter(Boolean))];
      if (farmaciaIds.length) {
        const { data: cadenas } = await supabase.rpc('nombre_cadena_por_farmacias', { p_farmacia_ids: farmaciaIds });
        if (cadenas?.length) {
          const mapa = new Map<number, string>(cadenas.map((c: any) => [c.farmacia_id, c.nombre_empresa]));
          enriquecidos = enriquecidos.map((r: any) =>
            r.farmacia && mapa.has(r.farmacia.id)
              ? { ...r, farmacia: { ...r.farmacia, empresa: { ...(r.farmacia.empresa || {}), nombre_empresa: mapa.get(r.farmacia.id) } } }
              : r);
        }
      }
      setResultados(enriquecidos as FarmaciaMedicamento[]);

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

  // ─── Búsqueda por medicamento_id (camino MÉDICO) ───
  // Idéntica a buscar() en embed/filtro/orden/enriquecimiento, PERO matchea por
  // medicamento_id (FK al catálogo global) en vez de ilike sobre el texto libre del
  // inventario → no falla por acento/variación de nombre. Solo farmacias (los médicos
  // no leen resultadosProveedores). Deposita en el MISMO estado `resultados`.
  const buscarPorMedicamento = useCallback(async (medicamentoId: number, incluirCatalogoGlobal = false) => {
    if (!medicamentoId) {
      setResultados([]);
      return;
    }
    setLoading(true);
    try {
      let q = supabase
        .from('farmacia_medicamentos')
        .select(`
          *,
          farmacia:farmacia_id!inner(id, nombre, direccion, telefono, email, encargado, horario, tipo, activo, empresa_id, empresa:empresa_id(nombre_empresa))
        `)
        .eq('medicamento_id', medicamentoId)
        .gt('stock_actual', 0);
      if (!incluirCatalogoGlobal) {
        q = q.not('farmacia.empresa_id', 'is', null).eq('farmacia.activo', true);
      }
      const { data: farmaciaData, error: farmaciaError } = await q.order('precio_unitario', { ascending: true });
      if (farmaciaError) throw farmaciaError;

      let enriquecidos = (farmaciaData || []) as any[];
      const farmaciaIds = [...new Set(enriquecidos.map((r: any) => r.farmacia?.id).filter(Boolean))];
      if (farmaciaIds.length) {
        const { data: cadenas } = await supabase.rpc('nombre_cadena_por_farmacias', { p_farmacia_ids: farmaciaIds });
        if (cadenas?.length) {
          const mapa = new Map<number, string>(cadenas.map((c: any) => [c.farmacia_id, c.nombre_empresa]));
          enriquecidos = enriquecidos.map((r: any) =>
            r.farmacia && mapa.has(r.farmacia.id)
              ? { ...r, farmacia: { ...r.farmacia, empresa: { ...(r.farmacia.empresa || {}), nombre_empresa: mapa.get(r.farmacia.id) } } }
              : r);
        }
      }
      setResultados(enriquecidos as FarmaciaMedicamento[]);
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
    buscarPorMedicamento,
    buscarPorFarmacia,
    resultadosFarmacias,
    buscarEnFarmacias,
    resultadosLaboratorios,
    buscarEnLaboratorios,
    resultadosProveedores,
    buscarEnProveedores,
  };
}
