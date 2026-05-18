import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

export type AdminRole = 'super_admin' | 'admin' | 'gerente' | 'vendedor' | 'soporte' | 'cliente';

export interface AdminUser {
  id: string;
  email: string;
  nombre: string;
  rol: AdminRole;
  pais_id?: string | null;
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

      // Consulta a la tabla CORRECTA: perfiles (no profiles)
      const { data: profile, error } = await supabase
        .from('perfiles')
        .select('*')
        .eq('id', user.id)
        .single();

      if (error) {
        console.error('Error cargando perfil:', error);
        setLoading(false);
        return;
      }

      // Verificar si el rol es de administrador (nivel >= 3 o roles específicos)
      const adminRoles = ['super_admin', 'admin', 'gerente'];
      const userRol = profile?.rol || 'cliente';

      if (profile && adminRoles.includes(userRol)) {
        setAdminUser({
          id: user.id,
          email: user.email || '',
          nombre: profile.nombre_completo || user.email || 'Usuario',
          rol: userRol as AdminRole,
          pais_id: profile.rol_id || null,
          activo: profile.activo ?? true,
          created_at: profile.created_at,
        });
        setIsAdmin(true);
      } else {
        setIsAdmin(false);
      }
    } catch (error) {
      console.error('Error verificando admin:', error);
      setIsAdmin(false);
    } finally {
      setLoading(false);
    }
  };

  return { adminUser, loading, isAdmin };
}
