import { useAuth } from './useAuth'
import { usePaisActivo } from './usePaisActivo'

/**
 * Hook para determinar automáticamente el pais_id según el contexto del usuario.
 * - Admin/Super Admin: usa el país activo seleccionado en el panel
 * - Medico/Admin_clinica/Paciente/Staff: usa el pais_id de su perfil
 */
export function usePaisFiltro() {
  const { perfil } = useAuth()
  const { paisActivo } = usePaisActivo()

  // Para admins: usar el país activo del contexto
  // Para otros usuarios: usar el país de su perfil
  const esAdmin = ['super_admin', 'admin', 'admin_pais'].includes(perfil?.rol || '')
  const paisId = esAdmin ? (paisActivo?.id || perfil?.pais_id) : perfil?.pais_id

  return {
    paisId,
    tienePais: !!paisId,
    esAdmin,
  }
}
