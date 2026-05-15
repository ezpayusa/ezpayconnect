import { Bell, Search, LogOut } from 'lucide-react';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { supabase } from '@/lib/supabase';
import { useNavigate } from 'react-router-dom';
import { useState } from 'react';

export function NavbarAdmin() {
  const { adminUser } = useAdminAuth();
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState('');

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate('/login');
  };

  return (
    <header className="h-16 bg-white shadow-sm border-b border-gray-100 flex items-center justify-between px-6 sticky top-0 z-40">
      <div className="flex-1 max-w-xl">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
          <input
            type="text"
            placeholder="Buscar médicos, clínicas, transacciones..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-gray-50 border border-gray-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB] focus:border-transparent transition-all"
          />
        </div>
      </div>

      <div className="flex items-center gap-4">
        <button className="relative p-2 text-gray-500 hover:text-[#1E5C8E] hover:bg-[#e8f0f8] rounded-lg transition-all">
          <Bell size={20} />
          <span className="absolute top-1 right-1 w-2 h-2 bg-red-500 rounded-full"></span>
        </button>

        <div className="h-8 w-px bg-gray-200"></div>

        <div className="flex items-center gap-3">
          <div className="text-right hidden sm:block">
            <p className="text-sm font-medium text-gray-800">{adminUser?.nombre || 'Administrador'}</p>
            <p className="text-xs text-gray-500 capitalize">{adminUser?.rol?.replace('_', ' ') || 'Super Admin'}</p>
          </div>
          <button
            onClick={handleLogout}
            className="p-2 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-all"
            title="Cerrar sesión"
          >
            <LogOut size={18} />
          </button>
        </div>
      </div>
    </header>
  );
}
