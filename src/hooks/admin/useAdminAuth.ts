import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';

// Fuente única de verdad: roles_catalogo. El back-office EzPay = super_admin
// (los roles granulares admin_pais/finanzas/ventas/... nunca existieron).
export type AdminRole = 'super_admin';

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
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    checkAdmin();
  }, []);

  const checkAdmin = async () => {
    console.log('[useAdminAuth] Iniciando verificación...');
    setLoading(true);
    setError(null);

    let isAdminLocal = false;  // FIX: variable local para rastrear admin

    try {
      // 1. Obtener usuario autenticado
      const { data: { user }, error: authError } = await supabase.auth.getUser();

      if (authError) {
        console.error('[useAdminAuth] Error auth:', authError);
        setError('Error de autenticación');
        return;
      }

      if (!user) {
        console.log('[useAdminAuth] No hay usuario autenticado');
        return;
      }

      console.log('[useAdminAuth] Usuario autenticado:', user.email, 'ID:', user.id);

      // 2. Obtener perfil de la tabla perfiles
      const { data: profile, error: profileError } = await supabase
        .from('perfiles')
        .select('*')
        .eq('id', user.id)
        .single();

      if (profileError) {
        console.error('[useAdminAuth] Error obteniendo perfil:', profileError);
        setError('Error obteniendo perfil: ' + profileError.message);
        return;
      }

      if (!profile) {
        console.log('[useAdminAuth] No se encontró perfil para el usuario');
        return;
      }

      console.log('[useAdminAuth] Perfil encontrado:', {
        email: profile.email,
        rol: profile.rol,
        nombre: profile.nombre_completo,
        activo: profile.activo
      });

      // 3. Verificar si el rol es admin
      const adminRoles = ['super_admin'];
      const userRol = profile?.rol;

      console.log('[useAdminAuth] Rol del usuario:', userRol);
      console.log('[useAdminAuth] ¿Es admin?', adminRoles.includes(userRol));

      if (userRol && adminRoles.includes(userRol)) {
        console.log('[useAdminAuth] ✅ Usuario ES admin');
        setAdminUser({
          id: user.id,
          email: user.email!,
          nombre: profile.nombre_completo || user.email!,
          rol: userRol as AdminRole,
          pais_id: profile.pais_id,
          activo: profile.activo ?? true,
          created_at: profile.created_at,
        });
        setIsAdmin(true);
        isAdminLocal = true;  // FIX: actualizar variable local
      } else {
        console.log('[useAdminAuth] ❌ Usuario NO es admin. Rol:', userRol);
        setIsAdmin(false);
      }
    } catch (error) {
      console.error('[useAdminAuth] Error inesperado:', error);
      setError('Error inesperado: ' + (error as Error).message);
    } finally {
      console.log('[useAdminAuth] Verificación completada. isAdmin:', isAdminLocal);
      setLoading(false);
    }
  };

  return { adminUser, loading, isAdmin, error };
}
