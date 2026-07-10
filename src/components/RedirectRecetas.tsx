import { Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { rutaHomePorRol } from '@/lib/rutas'

// /recetas se retiró (el médico receta desde /medico/recetas).
// El médico va a su portal; cualquier otro rol a su home (ya no recetan;
// el server los rechaza con PR002). No es un <Navigate> fijo porque eso
// mandaría a un admin al portal del médico.
export default function RedirectRecetas() {
  const { perfil } = useAuth()
  if (perfil?.rol === 'medico') return <Navigate to="/medico/recetas" replace />
  return <Navigate to={rutaHomePorRol(perfil)} replace />
}
