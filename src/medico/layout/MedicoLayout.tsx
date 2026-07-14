import { Outlet } from 'react-router-dom'
import { MedicoSidebar } from './MedicoSidebar'

export function MedicoLayout() {
  return (
    <div className="flex min-h-screen bg-slate-50">
      <MedicoSidebar />
      <main className="flex-1 ml-0 overflow-auto pt-14 md:pt-0">
        <Outlet />
      </main>
    </div>
  )
}
