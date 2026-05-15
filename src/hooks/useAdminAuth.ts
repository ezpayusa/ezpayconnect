import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { AdminRole, AdminUser } from '@/types/admin';

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
        .from('profiles')
        .select('*, rol:roles(*)')
        .eq('id', user.id)
        .single();

      if (profile?.rol?.nombre && ['super_admin', 'admin_pais', 'admin_finanzas'].includes(profile.rol.nombre)) {
        setAdminUser({
          id: user.id,
          email: user.email!,
          nombre: profile.nombre || user.email!,
          rol: profile.rol.nombre as AdminRole,
          pais_id: profile.pais_id,
          activo: profile.activo,
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
