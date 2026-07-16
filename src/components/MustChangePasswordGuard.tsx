import { useEffect } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { supabase } from '@/lib/supabase'

// Guard global: si el usuario logueado tiene user_metadata.must_change_password=true, lo manda a /set-password
// (con next = donde estaba) hasta que setee una contraseña propia. La barrera real de seguridad es no dejar
// credenciales temporales vivas; esto es el gate de UX que lo fuerza.
export default function MustChangePasswordGuard() {
  const navigate = useNavigate()
  const location = useLocation()
  useEffect(() => {
    let active = true
    const check = (user: any) => {
      if (!active || !user) return
      if (user.user_metadata?.must_change_password === true && location.pathname !== '/set-password') {
        navigate(`/set-password?next=${encodeURIComponent(location.pathname + location.search)}`, { replace: true })
      }
    }
    supabase.auth.getSession().then(({ data }) => check(data.session?.user ?? null))
    const sub = supabase.auth.onAuthStateChange((_e, session) => check(session?.user ?? null))
    return () => { active = false; sub.data.subscription.unsubscribe() }
  }, [location.pathname, location.search, navigate])
  return null
}
