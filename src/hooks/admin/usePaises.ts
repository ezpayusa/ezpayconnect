import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';

export interface PaisConfig {
  id: string;
  codigo: string;
  nombre: string;
  moneda: string;
  comisiones_activas: boolean;
  porcentaje_comision_default: number;
  activo: boolean;
}

export function usePaises() {
  const [paises, setPaises] = useState<PaisConfig[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchPaises();
  }, []);

  const fetchPaises = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('configuracion_pais')
        .select('*')
        .order('nombre');

      if (error) throw error;
      setPaises(data || []);
    } catch (error) {
      console.error('Error cargando países:', error);
    } finally {
      setLoading(false);
    }
  };

  const updatePais = async (id: string, updates: Partial<PaisConfig>) => {
    try {
      setSaving(true);
      const { error } = await supabase
        .from('configuracion_pais')
        .update(updates)
        .eq('id', id);

      if (error) throw error;
      await fetchPaises();
      return true;
    } catch (error) {
      console.error('Error actualizando país:', error);
      return false;
    } finally {
      setSaving(false);
    }
  };

  return { paises, loading, saving, fetchPaises, updatePais };
}