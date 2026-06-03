import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { CalendarDays, Clock, MapPin, X, Plus } from 'lucide-react'

export default function WebAppCitas() {
  const [tab, setTab] = useState<'proximas' | 'pasadas' | 'canceladas'>('proximas')

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">Mis Citas</h1>
          <p className="text-slate-500 mt-1">Gestiona tus consultas médicas</p>
        </div>
        <Button className="bg-gradient-to-r from-sky-500 to-indigo-500 hover:from-sky-600 hover:to-indigo-600">
          <Plus className="h-4 w-4 mr-1" /> Agendar
        </Button>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 bg-white p-1 rounded-xl border border-slate-200 w-fit">
        {(['proximas', 'pasadas', 'canceladas'] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
              tab === t ? 'bg-sky-50 text-sky-600' : 'text-slate-500 hover:text-slate-700'
            }`}
          >
            {t.charAt(0).toUpperCase() + t.slice(1)}
          </button>
        ))}
      </div>

      {/* Empty state */}
      <div className="text-center py-12">
        <CalendarDays className="h-12 w-12 text-slate-300 mx-auto mb-3" />
        <p className="text-slate-500">No tienes citas {tab}</p>
        <Button
          variant="outline"
          className="mt-4 border-sky-200 text-sky-600 hover:bg-sky-50"
          onClick={() => {}}
        >
          <Plus className="h-4 w-4 mr-1" /> Agendar primera cita
        </Button>
      </div>
    </div>
  )
}
