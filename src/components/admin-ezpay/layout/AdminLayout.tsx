import { Outlet } from 'react-router-dom';
import { SidebarAdmin } from './SidebarAdmin';
import { NavbarAdmin } from './NavbarAdmin';

export function AdminLayout() {
  return (
    <div className="min-h-screen bg-[#e8f0f8] flex">
      <SidebarAdmin />
      <div className="flex-1 flex flex-col ml-64">
        <NavbarAdmin />
        <main className="flex-1 p-6 overflow-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
