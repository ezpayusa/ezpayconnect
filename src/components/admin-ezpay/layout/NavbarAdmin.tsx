import { Bell, Search, LogOut, CheckCheck } from 'lucide-react';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { useNotificaciones } from '@/hooks/useNotificaciones';
import { supabase } from '@/lib/supabase';
import { useNavigate } from 'react-router-dom';
import { useState, useEffect, useRef } from 'react';

export function NavbarAdmin() {
  const { adminUser } = useAdminAuth();
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState('');
  const [showDropdown, setShowDropdown] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const {
    notificaciones,
    noLeidas,
    listarNotificaciones,
    marcarLeida,
    marcarTodasLeidas,
  } = useNotificaciones();

  // Cargar notificaciones al montar
  useEffect(() => {
    listarNotificaciones();

    // Actualizar cada 30 segundos
    const interval = setInterval(listarNotificaciones, 30000);
    return () => clearInterval(interval);
  }, [listarNotificaciones]);

  // Cerrar dropdown al hacer click fuera
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowDropdown(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate('/login');
  };

  const handleNotifClick = (notif: any) => {
    if (!notif.leida) {
      marcarLeida(notif.id);
    }
    if (notif.accion_url) {
      navigate(notif.accion_url);
    }
    setShowDropdown(false);
  };

  const getTipoColor = (tipo: string) => {
    const colors: Record<string, string> = {
      cita: 'bg-blue-500',
      pago: 'bg-green-500',
      empleado: 'bg-purple-500',
      sistema: 'bg-gray-500',
    };
    return colors[tipo] || 'bg-gray-500';
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
        {/* Campanita de Notificaciones */}
        <div className="relative" ref={dropdownRef}>
          <button 
            onClick={() => setShowDropdown(!showDropdown)}
            className="relative p-2 text-gray-500 hover:text-[#1E5C8E] hover:bg-[#e8f0f8] rounded-lg transition-all"
          >
            <Bell size={20} />
            {noLeidas > 0 && (
              <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] bg-red-500 text-white text-xs font-bold rounded-full flex items-center justify-center px-1">
                {noLeidas > 99 ? '99+' : noLeidas}
              </span>
            )}
          </button>

          {/* Dropdown de Notificaciones */}
          {showDropdown && (
            <div className="absolute right-0 top-full mt-2 w-80 bg-white rounded-xl shadow-lg border border-gray-200 z-50 overflow-hidden">
              <div className="p-3 border-b border-gray-100 flex items-center justify-between">
                <h3 className="font-semibold text-gray-800 text-sm">Notificaciones</h3>
                {noLeidas > 0 && (
                  <button
                    onClick={() => { marcarTodasLeidas(); }}
                    className="text-xs text-[#1E5C8E] hover:text-[#00f2ff] flex items-center gap-1"
                  >
                    <CheckCheck size={12} />
                    Marcar todas
                  </button>
                )}
              </div>

              <div className="max-h-80 overflow-y-auto">
                {notificaciones.length === 0 ? (
                  <div className="p-4 text-center text-gray-400 text-sm">
                    No hay notificaciones
                  </div>
                ) : (
                  notificaciones.slice(0, 5).map((notif) => (
                    <div
                      key={notif.id}
                      onClick={() => handleNotifClick(notif)}
                      className={`p-3 border-b border-gray-50 cursor-pointer hover:bg-gray-50 transition-colors ${
                        !notif.leida ? 'bg-blue-50/50' : ''
                      }`}
                    >
                      <div className="flex items-start gap-2">
                        <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${getTipoColor(notif.tipo)}`} />
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-gray-800 truncate">
                            {notif.titulo}
                          </p>
                          <p className="text-xs text-gray-500 truncate">
                            {notif.mensaje}
                          </p>
                          <p className="text-xs text-gray-400 mt-1">
                            {new Date(notif.created_at).toLocaleString('es-GT', {
                              day: '2-digit',
                              month: 'short',
                              hour: '2-digit',
                              minute: '2-digit',
                            })}
                          </p>
                        </div>
                        {!notif.leida && (
                          <span className="w-2 h-2 bg-[#00f2ff] rounded-full flex-shrink-0 mt-1" />
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>

              <div className="p-2 border-t border-gray-100">
                <button
                  onClick={() => { navigate('/notificaciones'); setShowDropdown(false); }}
                  className="w-full text-center text-xs text-[#1E5C8E] hover:text-[#00f2ff] py-1"
                >
                  Ver todas las notificaciones
                </button>
              </div>
            </div>
          )}
        </div>

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
