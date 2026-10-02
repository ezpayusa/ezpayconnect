import { useAuth } from '@/hooks/useAuth'
import ResumenUltimaVisita from './ResumenUltimaVisita'

// Desde la mig 340, contexto_ia_ultima_visita exige rol medico CON relación con el paciente: para
// cualquier otro rol (admin_clinica, enfermería, asistente_medico...) el botón daría siempre 403
// no_pertenencia. Acá sólo se decide el ROL; la relación la sigue decidiendo el servidor, y un médico
// sin relación ve el motivo del 403. Mientras el perfil carga no se muestra nada (sin parpadeo).
// Montarlo con key={pacienteId}, igual que ResumenUltimaVisita.
export default function ResumenUltimaVisitaMedico({ pacienteId, className }: { pacienteId: number; className?: string }) {
  const { loading, isMedico } = useAuth()
  if (loading || !isMedico()) return null
  return (
    <div className={className}>
      <ResumenUltimaVisita pacienteId={pacienteId} />
    </div>
  )
}
