// ═══════════════════════════════════════════════════════════════
// EZPAYCONNECT - HOOK usePlanes (ADAPTADO A ESTRUCTURA EXISTENTE)
// ═══════════════════════════════════════════════════════════════

import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { useToast } from '@/hooks/use-toast';
import {
  PlanBase,
  PlanConfiguracion,
  PlanAsignacion,
  PlanExcepcion,
  PlanHistorial,
  Pais,
  CrearPlanBaseDTO,
  CrearPlanConfigDTO,
  CrearPlanAsignacionDTO,
  CrearPlanExcepcionDTO,
  FiltrosPlanes,
  PaisCodigo,
  EstadoPlan,
} from '@/types/planes';

interface UsePlanesReturn {
  planesBase: PlanBase[];
  planesConfig: PlanConfiguracion[];
  paises: Pais[];
  asignaciones: PlanAsignacion[];
  excepciones: PlanExcepcion[];
  historial: PlanHistorial[];
  loading: boolean;
  error: string | null;

  crearPlanBase: (data: CrearPlanBaseDTO) => Promise<PlanBase | null>;
  actualizarPlanBase: (id: string, data: Partial<CrearPlanBaseDTO>) => Promise<boolean>;
  eliminarPlanBase: (id: string) => Promise<boolean>;

  crearPlanConfig: (data: CrearPlanConfigDTO) => Promise<PlanConfiguracion | null>;
  actualizarPlanConfig: (id: string, data: Partial<CrearPlanConfigDTO>) => Promise<boolean>;
  eliminarPlanConfig: (id: string) => Promise<boolean>;

  crearAsignacion: (data: CrearPlanAsignacionDTO) => Promise<PlanAsignacion | null>;
  actualizarAsignacion: (id: string, data: Partial<CrearPlanAsignacionDTO>) => Promise<boolean>;
  cancelarAsignacion: (id: string, motivo: string) => Promise<boolean>;
  renovarAsignacion: (id: string) => Promise<boolean>;

  crearExcepcion: (data: CrearPlanExcepcionDTO) => Promise<PlanExcepcion | null>;
  actualizarExcepcion: (id: string, data: Partial<CrearPlanExcepcionDTO>) => Promise<boolean>;
  desactivarExcepcion: (id: string) => Promise<boolean>;

  getPlanesPorPais: (paisId: string) => PlanConfiguracion[];
  getPlanRecomendado: (medicos: number, pacientes: number, paisId: string) => PlanConfiguracion | null;
  calcularPrecioConDescuento: (configId: string, entidadId?: string) => { precio: number; descuento: number; tipo: string };
  getEstadisticas: () => {
    totalActivos: number;
    totalIngresosMensual: number;
    tasaRenovacion: number;
    planesPopulares: { plan: string; count: number }[];
  };

  recargar: () => void;
}

export function usePlanes(filtros?: FiltrosPlanes): UsePlanesReturn {
  const { toast } = useToast();
  const [planesBase, setPlanesBase] = useState<PlanBase[]>([]);
  const [planesConfig, setPlanesConfig] = useState<PlanConfiguracion[]>([]);
  const [paises, setPaises] = useState<Pais[]>([]);
  const [asignaciones, setAsignaciones] = useState<PlanAsignacion[]>([]);
  const [excepciones, setExcepciones] = useState<PlanExcepcion[]>([]);
  const [historial, setHistorial] = useState<PlanHistorial[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargarDatos = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // Planes Base (filtrar solo tipo='medico' para módulo médico)
      let queryBase = supabase.from('planes_base').select('*').eq('activo', true);
      if (filtros?.tipo) queryBase = queryBase.eq('tipo', filtros.tipo);
      else queryBase = queryBase.eq('tipo', 'medico');
      const { data: baseData, error: baseError } = await queryBase;
      if (baseError) throw baseError;
      setPlanesBase(baseData || []);

      // Países desde configuracion_pais
      const { data: paisesData, error: paisesError } = await supabase
        .from('configuracion_pais')
        .select('*')
        .eq('activo', true);
      if (paisesError) throw paisesError;
      setPaises(paisesData || []);

      // Configuraciones con relaciones
      let queryConfig = supabase
        .from('planes_configuracion')
        .select('*, plan_base:plan_base_id(*), pais:pais_id(*)')
        .eq('activo', true);
      const { data: configData, error: configError } = await queryConfig;
      if (configError) throw configError;
      setPlanesConfig(configData || []);

      // Asignaciones (si tabla existe)
      try {
        let queryAsig = supabase
          .from('planes_asignaciones')
          .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*)), medico:medico_id(id, nombre, email, especialidad)')
          .order('created_at', { ascending: false });
        if (filtros?.estado) queryAsig = queryAsig.eq('estado', filtros.estado);
        const { data: asigData } = await queryAsig;
        setAsignaciones(asigData || []);
      } catch {
        setAsignaciones([]);
      }

      // Excepciones
      const { data: excData, error: excError } = await supabase
        .from('planes_excepciones')
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .order('created_at', { ascending: false });
      if (excError) throw excError;
      setExcepciones(excData || []);

      // Historial
      const { data: histData, error: histError } = await supabase
        .from('planes_historial')
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .order('created_at', { ascending: false })
        .limit(100);
      if (histError) throw histError;
      setHistorial(histData || []);

    } catch (err: any) {
      setError(err.message);
      toast({ title: 'Error al cargar planes', description: err.message, variant: 'destructive' });
    } finally {
      setLoading(false);
    }
  }, [filtros, toast]);

  useEffect(() => { cargarDatos(); }, [cargarDatos]);

  // CRUD Planes Base
  const crearPlanBase = async (data: CrearPlanBaseDTO): Promise<PlanBase | null> => {
    try {
      const { data: result, error } = await supabase.from('planes_base').insert(data).select().single();
      if (error) throw error;
      setPlanesBase(prev => [...prev, result]);
      toast({ title: 'Plan creado', description: `${result.nombre} creado exitosamente` });
      return result;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return null;
    }
  };

  const actualizarPlanBase = async (id: string, data: Partial<CrearPlanBaseDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_base').update(data).eq('id', id);
      if (error) throw error;
      setPlanesBase(prev => prev.map(p => p.id === id ? { ...p, ...data } : p));
      toast({ title: 'Plan actualizado' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  const eliminarPlanBase = async (id: string): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_base').update({ activo: false }).eq('id', id);
      if (error) throw error;
      setPlanesBase(prev => prev.filter(p => p.id !== id));
      toast({ title: 'Plan desactivado' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  // CRUD Configuración
  const crearPlanConfig = async (data: CrearPlanConfigDTO): Promise<PlanConfiguracion | null> => {
    try {
      const { data: result, error } = await supabase
        .from('planes_configuracion')
        .insert(data)
        .select('*, plan_base:plan_base_id(*), pais:pais_id(*)')
        .single();
      if (error) throw error;
      setPlanesConfig(prev => [...prev, result]);
      toast({ title: 'Configuración creada' });
      return result;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return null;
    }
  };

  const actualizarPlanConfig = async (id: string, data: Partial<CrearPlanConfigDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_configuracion').update(data).eq('id', id);
      if (error) throw error;
      setPlanesConfig(prev => prev.map(p => p.id === id ? { ...p, ...data } : p));
      toast({ title: 'Configuración actualizada' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  const eliminarPlanConfig = async (id: string): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_configuracion').update({ activo: false }).eq('id', id);
      if (error) throw error;
      setPlanesConfig(prev => prev.filter(p => p.id !== id));
      toast({ title: 'Configuración desactivada' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  // CRUD Asignaciones (crea tabla si no existe)
  const crearAsignacion = async (data: CrearPlanAsignacionDTO): Promise<PlanAsignacion | null> => {
    try {
      const { data: result, error } = await supabase
        .from('planes_asignaciones')
        .insert({ ...data, estado: 'activo' })
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .single();
      if (error) throw error;
      setAsignaciones(prev => [result, ...prev]);

      await supabase.from('planes_historial').insert({
        entidad_id: data.medico_id,
        tipo_entidad: 'medico',
        plan_config_id: data.plan_config_id,
        accion: 'activacion',
        detalle: { precio_nuevo: data.precio_aplicado, moneda: data.moneda, motivo: 'Nueva suscripción' },
        usuario_admin_id: (await supabase.auth.getUser()).data.user?.id,
      });

      toast({ title: 'Suscripción creada' });
      return result;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return null;
    }
  };

  const actualizarAsignacion = async (id: string, data: Partial<CrearPlanAsignacionDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_asignaciones').update(data).eq('id', id);
      if (error) throw error;
      setAsignaciones(prev => prev.map(a => a.id === id ? { ...a, ...data } : a));
      toast({ title: 'Suscripción actualizada' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  const cancelarAsignacion = async (id: string, motivo: string): Promise<boolean> => {
    try {
      const asignacion = asignaciones.find(a => a.id === id);
      if (!asignacion) throw new Error('Asignación no encontrada');

      const { error } = await supabase
        .from('planes_asignaciones')
        .update({ estado: 'cancelado', fecha_fin: new Date().toISOString() })
        .eq('id', id);
      if (error) throw error;

      await supabase.from('planes_historial').insert({
        entidad_id: asignacion.medico_id,
        tipo_entidad: 'medico',
        plan_config_id: asignacion.plan_config_id,
        accion: 'cancelacion',
        detalle: { precio_anterior: asignacion.precio_aplicado, moneda: asignacion.moneda, motivo },
        usuario_admin_id: (await supabase.auth.getUser()).data.user?.id,
      });

      setAsignaciones(prev => prev.map(a => a.id === id ? { ...a, estado: 'cancelado' as EstadoPlan } : a));
      toast({ title: 'Suscripción cancelada' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  const renovarAsignacion = async (id: string): Promise<boolean> => {
    try {
      const asignacion = asignaciones.find(a => a.id === id);
      if (!asignacion) throw new Error('Asignación no encontrada');

      const nuevaFechaFin = asignacion.tipo_ciclo === 'anual'
        ? new Date(new Date(asignacion.fecha_fin || new Date()).setFullYear(new Date().getFullYear() + 1)).toISOString()
        : new Date(new Date(asignacion.fecha_fin || new Date()).setMonth(new Date().getMonth() + 1)).toISOString();

      const { error } = await supabase
        .from('planes_asignaciones')
        .update({ fecha_fin: nuevaFechaFin, estado: 'activo' })
        .eq('id', id);
      if (error) throw error;

      await supabase.from('planes_historial').insert({
        entidad_id: asignacion.medico_id,
        tipo_entidad: 'medico',
        plan_config_id: asignacion.plan_config_id,
        accion: 'renovacion',
        detalle: { precio_nuevo: asignacion.precio_aplicado, moneda: asignacion.moneda, motivo: 'Renovación automática' },
        usuario_admin_id: (await supabase.auth.getUser()).data.user?.id,
      });

      setAsignaciones(prev => prev.map(a => a.id === id ? { ...a, fecha_fin: nuevaFechaFin, estado: 'activo' } : a));
      toast({ title: 'Suscripción renovada' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  // CRUD Excepciones
  const crearExcepcion = async (data: CrearPlanExcepcionDTO): Promise<PlanExcepcion | null> => {
    try {
      const { data: result, error } = await supabase
        .from('planes_excepciones')
        .insert({ ...data, activo: true })
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .single();
      if (error) throw error;
      setExcepciones(prev => [result, ...prev]);
      toast({ title: 'Excepción creada' });
      return result;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return null;
    }
  };

  const actualizarExcepcion = async (id: string, data: Partial<CrearPlanExcepcionDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_excepciones').update(data).eq('id', id);
      if (error) throw error;
      setExcepciones(prev => prev.map(e => e.id === id ? { ...e, ...data } : e));
      toast({ title: 'Excepción actualizada' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  const desactivarExcepcion = async (id: string): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_excepciones').update({ activo: false }).eq('id', id);
      if (error) throw error;
      setExcepciones(prev => prev.map(e => e.id === id ? { ...e, activo: false } : e));
      toast({ title: 'Excepción desactivada' });
      return true;
    } catch (err: any) {
      toast({ title: 'Error', description: err.message, variant: 'destructive' });
      return false;
    }
  };

  // Utilidades
  const getPlanesPorPais = useCallback((paisId: string) => {
    return planesConfig.filter(p => p.pais_id === paisId);
  }, [planesConfig]);

  const getPlanRecomendado = useCallback((medicos: number, pacientes: number, paisId: string): PlanConfiguracion | null => {
    const planes = getPlanesPorPais(paisId);
    return planes[0] || null;
  }, [getPlanesPorPais]);

  const calcularPrecioConDescuento = useCallback((configId: string, entidadId?: string) => {
    const config = planesConfig.find(p => p.id === configId);
    if (!config) return { precio: 0, descuento: 0, tipo: 'ninguno' };

    let precio = config.precio_local;
    let descuento = 0;
    let tipo = 'precio_base';

    const ahora = new Date().toISOString();
    const excs = excepciones.filter(e => 
      e.plan_config_id === configId && 
      e.activo &&
      e.fecha_inicio <= ahora &&
      (!e.fecha_fin || e.fecha_fin >= ahora) &&
      (!e.entidad_id || e.entidad_id === entidadId)
    );

    if (excs.length > 0) {
      const mayorDescuento = excs.reduce((max, e) => {
        const valorDesc = e.precio_especial > 0 ? precio - e.precio_especial : 0;
        return valorDesc > max.valor ? { valor: valorDesc, tipo: 'precio_especial' } : max;
      }, { valor: 0, tipo: '' });

      if (mayorDescuento.valor > 0) {
        descuento = mayorDescuento.valor;
        precio = Math.max(0, precio - descuento);
        tipo = mayorDescuento.tipo;
      }
    }

    return { precio: Math.round(precio * 100) / 100, descuento: Math.round(descuento * 100) / 100, tipo };
  }, [planesConfig, excepciones]);

  const getEstadisticas = useCallback(() => {
    const activos = asignaciones.filter(a => a.estado === 'activo');
    const totalIngresos = activos.reduce((sum, a) => sum + (a.precio_aplicado || 0), 0);
    const renovados = activos.filter(a => a.auto_renovar).length;

    const conteoPlanes: Record<string, number> = {};
    activos.forEach(a => {
      const nombre = a.plan_configuracion?.plan_base?.nombre || 'Desconocido';
      conteoPlanes[nombre] = (conteoPlanes[nombre] || 0) + 1;
    });

    return {
      totalActivos: activos.length,
      totalIngresosMensual: Math.round(totalIngresos * 100) / 100,
      tasaRenovacion: activos.length > 0 ? Math.round((renovados / activos.length) * 100) : 0,
      planesPopulares: Object.entries(conteoPlanes).map(([plan, count]) => ({ plan, count })).sort((a, b) => b.count - a.count),
    };
  }, [asignaciones]);

  return {
    planesBase, planesConfig, paises, asignaciones, excepciones, historial,
    loading, error,
    crearPlanBase, actualizarPlanBase, eliminarPlanBase,
    crearPlanConfig, actualizarPlanConfig, eliminarPlanConfig,
    crearAsignacion, actualizarAsignacion, cancelarAsignacion, renovarAsignacion,
    crearExcepcion, actualizarExcepcion, desactivarExcepcion,
    getPlanesPorPais, getPlanRecomendado, calcularPrecioConDescuento, getEstadisticas,
    recargar: cargarDatos,
  };
}
