// EZPAYCONNECT - HOOK usePlanes (COMPLETO - Dia 4)

import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { toast } from 'sonner';
import type {
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
  EstadoPlan,
  CicloFacturacion,
  MetodoPago,
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
  crearAsignacionCheckout: (datos: {
    planId: string;
    configuracionId: string;
    ciclo: CicloFacturacion;
    metodoPago: MetodoPago;
    precioFinal: number;
    moneda: string;
  }) => Promise<PlanAsignacion | null>;
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
      let queryBase = supabase.from('planes_base').select('*').eq('activo', true);
      if (filtros?.tipo) queryBase = queryBase.eq('tipo', filtros.tipo);
      const { data: baseData, error: baseError } = await queryBase;
      if (baseError) throw baseError;
      setPlanesBase(baseData || []);

      const { data: paisesData, error: paisesError } = await supabase
        .from('configuracion_pais')
        .select('*')
        .eq('activo', true);
      if (paisesError) throw paisesError;
      setPaises(paisesData || []);

      let queryConfig = supabase
        .from('planes_configuracion')
        .select('*, plan_base:plan_base_id(*), pais:pais_id(*)')
        .eq('activo', true);
      if (filtros?.pais_id) queryConfig = queryConfig.eq('pais_id', filtros.pais_id);
      const { data: configData, error: configError } = await queryConfig;
      if (configError) throw configError;
      const configs = configData || [];
      setPlanesConfig(configs);

      try {
        let queryAsig = supabase
          .from('planes_asignaciones')
          .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
          .order('created_at', { ascending: false });
        if (filtros?.estado) queryAsig = queryAsig.eq('estado', filtros.estado);
        const { data: asigData } = await queryAsig;
        let asigs = asigData || [];
        if (filtros?.pais_id) {
          const configIds = new Set(configs.map(c => c.id));
          asigs = asigs.filter(a => configIds.has(a.plan_config_id || a.configuracion_id || ''));
        }
        setAsignaciones(asigs);
      } catch {
        setAsignaciones([]);
      }

      const { data: excData, error: excError } = await supabase
        .from('planes_excepciones')
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .order('created_at', { ascending: false });
      if (excError) throw excError;
      let excs = excData || [];
      if (filtros?.pais_id) {
        const configIds = new Set(configs.map(c => c.id));
        excs = excs.filter(e => configIds.has(e.plan_config_id || e.plan_id || ''));
      }
      setExcepciones(excs);

      const { data: histData, error: histError } = await supabase
        .from('planes_historial')
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .order('created_at', { ascending: false })
        .limit(100);
      if (histError) throw histError;
      let hists = histData || [];
      if (filtros?.pais_id) {
        const configIds = new Set(configs.map(c => c.id));
        hists = hists.filter(h => configIds.has(h.plan_config_id || ''));
      }
      setHistorial(hists);

    } catch (err: any) {
      setError(err.message);
      console.error('Error al cargar planes:', err.message);
      toast.error('Error al cargar planes', { description: err.message });
    } finally {
      setLoading(false);
    }
    // Dep en PRIMITIVAS (no en el objeto `filtros`): PlanesPage pasa `{ pais_id }` como literal nuevo
    // en cada render → con [filtros] cargarDatos se recreaba siempre → useEffect([cargarDatos]) re-fetcheaba
    // en loop infinito. Con primitivas, cargarDatos solo cambia cuando cambian los valores reales.
  }, [filtros?.pais_id, filtros?.tipo, filtros?.estado]);

  useEffect(() => { cargarDatos(); }, [cargarDatos]);

  const crearPlanBase = async (data: CrearPlanBaseDTO): Promise<PlanBase | null> => {
    try {
      const { data: result, error } = await supabase.from('planes_base').insert(data).select().single();
      if (error) throw error;
      setPlanesBase(prev => [...prev, result]);
      toast.success('Plan creado', { description: `${result.nombre} se creó exitosamente` });
      return result;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al crear el plan', { description: err.message });
      return null;
    }
  };

  const actualizarPlanBase = async (id: string, data: Partial<CrearPlanBaseDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_base').update(data).eq('id', id);
      if (error) throw error;
      setPlanesBase(prev => prev.map(p => p.id === id ? { ...p, ...data } : p));
      toast.success('Plan actualizado');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al actualizar el plan', { description: err.message });
      return false;
    }
  };

  const eliminarPlanBase = async (id: string): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_base').update({ activo: false }).eq('id', id);
      if (error) throw error;
      setPlanesBase(prev => prev.filter(p => p.id !== id));
      toast.success('Plan desactivado');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al desactivar el plan', { description: err.message });
      return false;
    }
  };

  const crearPlanConfig = async (data: CrearPlanConfigDTO): Promise<PlanConfiguracion | null> => {
    try {
      const { data: result, error } = await supabase
        .from('planes_configuracion')
        .insert(data)
        .select('*, plan_base:plan_base_id(*), pais:pais_id(*)')
        .single();
      if (error) throw error;
      setPlanesConfig(prev => [...prev, result]);
      toast.success('Configuración creada');
      return result;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al crear la configuración', { description: err.message });
      return null;
    }
  };

  const actualizarPlanConfig = async (id: string, data: Partial<CrearPlanConfigDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_configuracion').update(data).eq('id', id);
      if (error) throw error;
      setPlanesConfig(prev => prev.map(p => p.id === id ? { ...p, ...data } : p));
      toast.success('Configuración actualizada');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al actualizar la configuración', { description: err.message });
      return false;
    }
  };

  const eliminarPlanConfig = async (id: string): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_configuracion').update({ activo: false }).eq('id', id);
      if (error) throw error;
      setPlanesConfig(prev => prev.filter(p => p.id !== id));
      toast.success('Configuración desactivada');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al desactivar la configuración', { description: err.message });
      return false;
    }
  };

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
        entidad_id: data.medico_id || data.usuario_id,
        tipo_entidad: 'medico',
        plan_config_id: data.plan_config_id,
        accion: 'activacion',
        detalle: { precio_nuevo: data.precio_aplicado, moneda: data.moneda, motivo: 'Nueva suscripcion' },
        usuario_admin_id: (await supabase.auth.getUser()).data.user?.id,
      });

      toast.success('Asignación creada');
      return result;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al crear la asignación', { description: err.message });
      return null;
    }
  };

  const crearAsignacionCheckout = async (datos: {
    planId: string;
    configuracionId: string;
    ciclo: CicloFacturacion;
    metodoPago: MetodoPago;
    precioFinal: number;
    moneda: string;
  }): Promise<PlanAsignacion | null> => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Usuario no autenticado');

      const fechaInicio = new Date().toISOString();
      const fechaFin = datos.ciclo === 'mensual'
        ? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
        : new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString();

      const { data: result, error: insertError } = await supabase
        .from('planes_asignaciones')
        .insert({
          usuario_id: user.id,
          plan_id: datos.planId,
          configuracion_id: datos.configuracionId,
          plan_config_id: datos.configuracionId,
          estado: 'activo',
          ciclo_facturacion: datos.ciclo,
          tipo_ciclo: datos.ciclo,
          metodo_pago: datos.metodoPago,
          precio_final: datos.precioFinal,
          precio_aplicado: datos.precioFinal,
          moneda: datos.moneda,
          fecha_inicio: fechaInicio,
          fecha_fin: fechaFin,
          renovacion_automatica: true,
          auto_renovar: true,
        })
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .single();

      if (insertError) throw insertError;

      await supabase.from('planes_historial').insert({
        entidad_id: user.id,
        tipo_entidad: 'usuario',
        plan_config_id: datos.configuracionId,
        accion: 'asignacion_creada',
        detalle: {
          precio_nuevo: datos.precioFinal,
          moneda: datos.moneda,
          motivo: `Checkout: ${datos.ciclo}, metodo: ${datos.metodoPago}`,
        },
        usuario_admin_id: user.id,
        fecha_accion: fechaInicio,
      });

      setAsignaciones(prev => [result, ...prev]);
      toast.success('Suscripción activada', { description: '¡Bienvenido a tu nuevo plan!' });
      return result;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al procesar el pago', { description: err.message });
      return null;
    }
  };

  const actualizarAsignacion = async (id: string, data: Partial<CrearPlanAsignacionDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_asignaciones').update(data).eq('id', id);
      if (error) throw error;
      setAsignaciones(prev => prev.map(a => a.id === id ? { ...a, ...data } : a));
      toast.success('Asignación actualizada');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al actualizar la asignación', { description: err.message });
      return false;
    }
  };

  const cancelarAsignacion = async (id: string, motivo: string): Promise<boolean> => {
    try {
      const asignacion = asignaciones.find(a => a.id === id);
      if (!asignacion) throw new Error('Asignacion no encontrada');

      const { error } = await supabase
        .from('planes_asignaciones')
        .update({ estado: 'cancelado', fecha_fin: new Date().toISOString() })
        .eq('id', id);
      if (error) throw error;

      await supabase.from('planes_historial').insert({
        entidad_id: asignacion.medico_id || asignacion.usuario_id,
        tipo_entidad: 'medico',
        plan_config_id: asignacion.plan_config_id,
        accion: 'cancelacion',
        detalle: { precio_anterior: asignacion.precio_aplicado, moneda: asignacion.moneda, motivo },
        usuario_admin_id: (await supabase.auth.getUser()).data.user?.id,
      });

      setAsignaciones(prev => prev.map(a => a.id === id ? { ...a, estado: 'cancelado' as EstadoPlan } : a));
      toast.success('Suscripción cancelada');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al cancelar la suscripción', { description: err.message });
      return false;
    }
  };

  const renovarAsignacion = async (id: string): Promise<boolean> => {
    try {
      const asignacion = asignaciones.find(a => a.id === id);
      if (!asignacion) throw new Error('Asignacion no encontrada');

      const nuevaFechaFin = asignacion.tipo_ciclo === 'anual'
        ? new Date(new Date(asignacion.fecha_fin || new Date()).setFullYear(new Date().getFullYear() + 1)).toISOString()
        : new Date(new Date(asignacion.fecha_fin || new Date()).setMonth(new Date().getMonth() + 1)).toISOString();

      const { error } = await supabase
        .from('planes_asignaciones')
        .update({ fecha_fin: nuevaFechaFin, estado: 'activo' })
        .eq('id', id);
      if (error) throw error;

      await supabase.from('planes_historial').insert({
        entidad_id: asignacion.medico_id || asignacion.usuario_id,
        tipo_entidad: 'medico',
        plan_config_id: asignacion.plan_config_id,
        accion: 'renovacion',
        detalle: { precio_nuevo: asignacion.precio_aplicado, moneda: asignacion.moneda, motivo: 'Renovacion automatica' },
        usuario_admin_id: (await supabase.auth.getUser()).data.user?.id,
      });

      setAsignaciones(prev => prev.map(a => a.id === id ? { ...a, fecha_fin: nuevaFechaFin, estado: 'activo' } : a));
      toast.success('Suscripción renovada');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al renovar la suscripción', { description: err.message });
      return false;
    }
  };

  const crearExcepcion = async (data: CrearPlanExcepcionDTO): Promise<PlanExcepcion | null> => {
    try {
      const { data: result, error } = await supabase
        .from('planes_excepciones')
        .insert({ ...data, activo: true })
        .select('*, plan_configuracion:plan_config_id(*, plan_base:plan_base_id(*))')
        .single();
      if (error) throw error;
      setExcepciones(prev => [result, ...prev]);
      toast.success('Excepción creada');
      return result;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al crear la excepción', { description: err.message });
      return null;
    }
  };

  const actualizarExcepcion = async (id: string, data: Partial<CrearPlanExcepcionDTO>): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_excepciones').update(data).eq('id', id);
      if (error) throw error;
      setExcepciones(prev => prev.map(e => e.id === id ? { ...e, ...data } : e));
      toast.success('Excepción actualizada');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al actualizar la excepción', { description: err.message });
      return false;
    }
  };

  const desactivarExcepcion = async (id: string): Promise<boolean> => {
    try {
      const { error } = await supabase.from('planes_excepciones').update({ activo: false }).eq('id', id);
      if (error) throw error;
      setExcepciones(prev => prev.map(e => e.id === id ? { ...e, activo: false } : e));
      toast.success('Excepción desactivada');
      return true;
    } catch (err: any) {
      setError(err.message);
      toast.error('Error al desactivar la excepción', { description: err.message });
      return false;
    }
  };

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
    crearAsignacion, crearAsignacionCheckout, actualizarAsignacion, cancelarAsignacion, renovarAsignacion,
    crearExcepcion, actualizarExcepcion, desactivarExcepcion,
    getPlanesPorPais, getPlanRecomendado, calcularPrecioConDescuento, getEstadisticas,
    recargar: cargarDatos,
  };
}