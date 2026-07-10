import { MessageCircle } from 'lucide-react'

// D1: el chat del paciente esta DESHABILITADO. No existe UI de chat del lado
// del medico (0 archivos en src/medico/), por lo que ningun mensaje enviado
// aqui puede ser leido ni respondido. La ruta se conserva viva a proposito:
// las notificaciones ya emitidas apuntan a /paciente/chat y a /medico/chat,
// y deben aterrizar en un aviso, no en un 404.
// La tabla chat_mensajes, el hook useWebAppChat y la RPC notificar_chat
// quedan intactos. Reactivar = revertir este archivo + reponer las entradas
// de WebAppSidebar y WebAppDashboard.
export default function WebAppChat() {
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center">
      <div className="w-14 h-14 rounded-full bg-slate-100 flex items-center justify-center mb-4">
        <MessageCircle className="h-7 w-7 text-slate-400" />
      </div>
      <h1 className="text-xl font-semibold text-slate-800">
        Mensajería no disponible
      </h1>
      <p className="text-slate-500 mt-2 max-w-md">
        Esta función aún no está habilitada. Para consultas sobre tu tratamiento,
        comunicate directamente con tu clínica o agendá una cita.
      </p>
    </div>
  )
}
