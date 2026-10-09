import { useEffect, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { rutaHomePorRol } from '@/lib/rutas'
import { esPacienteActual } from '@/lib/esPaciente'

function Spinner() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
    </div>
  )
}

// Ruta "/": manda a cada cuenta a su casa. Con perfil, por rol (rutaHomePorRol). Sin perfil puede ser un paciente
// (vive en `pacientes`, no en perfiles; p. ej. el que vuelve del correo de confirmación): se consulta solo en ese caso.
export default function RootRedirect() {
  const { user, perfil, loading } = useAuth()
  const uid: string | undefined = user?.id
  const sinPerfil = !loading && !!uid && !perfil
  const [paciente, setPaciente] = useState<{ uid: string; es: boolean } | null>(null)

  useEffect(() => {
    if (!sinPerfil || !uid) return
    let vigente = true
    esPacienteActual(uid).then((es) => { if (vigente) setPaciente({ uid, es }) })
    return () => { vigente = false }
  }, [sinPerfil, uid])

  if (loading) return <Spinner />
  if (!user) return <Navigate to="/login" replace />
  if (perfil) return <Navigate to={rutaHomePorRol(perfil)} replace />
  if (!paciente || paciente.uid !== uid) return <Spinner />
  return <Navigate to={paciente.es ? '/paciente' : rutaHomePorRol(null)} replace />
}
