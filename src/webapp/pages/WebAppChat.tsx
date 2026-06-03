import { MessageCircle } from 'lucide-react'

export default function WebAppChat() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Chat con mi Médico</h1>
        <p className="text-slate-500 mt-1">Mensajería directa con tu médico</p>
      </div>
      <div className="text-center py-12">
        <MessageCircle className="h-12 w-12 text-slate-300 mx-auto mb-3" />
        <p className="text-slate-500">Selecciona un médico para chatear</p>
      </div>
    </div>
  )
}
