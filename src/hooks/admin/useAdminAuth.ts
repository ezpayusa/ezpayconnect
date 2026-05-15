import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';

export type AdminRole = 'super_admin' | 'admin_pais' | 'admin_finanzas' | 'admin_soporte' | 'admin_ventas';

export interface AdminUser {
  id: string;
  email: string;
  nombre: string;
  rol: AdminRole;
  pais_id?: string;
  activo: boolean;
  created_at: string;
}

export function useAdminAuth() {
  const [adminUser, setAdminUser] = useState<AdminUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [isAdmin, setIsAdmin] = useState(false);

  useEffect(() => {
    checkAdmin();
  }, []);

  const checkAdmin = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        setLoading(false);
        return;
      }

      const { data: profile } = await supabase
        .from('perfiles')
        .select('*')
        .eq('id', user.id)
        .single();

      const adminRoles = ['super_admin', 'admin_pais', 'admin_finanzas'];
      const userRol = profile?.rol;
      
      if (userRol && adminRoles.includes(userRol)) {
        setAdminUser({
          id: user.id,
          email: user.email!,
          nombre: profile.nombre_completo || user.email!,
          rol: userRol as AdminRole,
          pais_id: profile.pais_id,
          activo: true,
          created_at: profile.created_at,
        });
        setIsAdmin(true);
      }
    } catch (error) {
      console.error('Error verificando admin:', error);
    } finally {
      setLoading(false);
    }
  };

  return { adminUser, loading, isAdmin };
}