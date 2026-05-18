import { NavLink, useLocation } from 'react-router-dom';
import { 
  LayoutDashboard, 
  Globe, 
  CreditCard,
  Stethoscope, 
  Building2, 
  FlaskConical, 
  Truck, 
  AlertCircle, 
  DollarSign, 
  FileText, 
  BarChart3,
  Shield, 
  ChevronLeft 
} from 'lucide-react';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';

const menuItems = [
  { path: '/admin-ezpay', icon: LayoutDashboard, label: 'Dashboard' },
  { path: '/admin-ezpay/paises', icon: Globe, label: 'Países' },
  { path: '/admin-ezpay/planes-todos', icon: CreditCard, label: 'Todos los Planes' },
  { path: '/admin-ezpay/planes-medico', icon: Stethoscope, label: 'Planes Médico' },
  { path: '/admin-ezpay/planes-clinica', icon: Building2, label: 'Planes Clínica' },
  { path: '/admin-ezpay/planes-lab', icon: FlaskConical, label: 'Planes Lab/Farmacia' },
  { path: '/admin-ezpay/planes-visitador', icon: Truck, label: 'Planes Visitador' },
  { path: '/admin-ezpay/excepciones', icon: AlertCircle, label: 'Excepciones' },
  { path: '/admin-ezpay/finanzas', icon: DollarSign, label: 'Finanzas' },
  { path: '/admin-ezpay/reportes', icon: BarChart3, label: 'Reportes EZPay' },
  { path: '/reportes', icon: FileText, label: 'Reportes Médico' },
  { path: '/admin-ezpay/roles', icon: Shield, label: 'Roles' },
];

export function SidebarAdmin() {
  const location = useLocation();
  const { adminUser } = useAdminAuth();

  return (
    <aside className="fixed left-0 top-0 h-full w-64 bg-[#87CEEB] shadow-xl flex flex-col z-50">
      <div className="p-6 border-b border-white/20">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-white rounded-lg flex items-center justify-center">
            <span className="text-[#87CEEB] font-bold text-xl">E</span>
          </div>
          <div>
            <h1 className="text-white font-bold text-lg leading-tight">EZPayConnect</h1>
            <p className="text-white/70 text-xs">Panel Maestro</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 py-4 px-3 space-y-1 overflow-y-auto">
        {menuItems.map((item) => {
          const isActive = location.pathname === item.path || 
                          (item.path !== '/admin-ezpay' && location.pathname.startsWith(item.path));
          const Icon = item.icon;

          return (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive: active }) =>
                `flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-200 ${
                  active || isActive
                    ? 'bg-white text-[#1E5C8E] shadow-md font-semibold'
                    : 'text-white/80 hover:bg-white/10 hover:text-white'
                }`
              }
            >
              <Icon size={20} />
              <span className="text-sm">{item.label}</span>
            </NavLink>
          );
        })}
      </nav>

      <div className="p-4 border-t border-white/20">
        <div className="flex items-center gap-3 px-4 py-2">
          <div className="w-8 h-8 bg-white/20 rounded-full flex items-center justify-center">
            <span className="text-white text-xs font-bold">
              {adminUser?.nombre?.charAt(0).toUpperCase() || 'A'}
            </span>
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-white text-sm font-medium truncate">{adminUser?.nombre || 'Admin'}</p>
            <p className="text-white/60 text-xs truncate capitalize">{adminUser?.rol?.replace('_', ' ') || 'Super Admin'}</p>
          </div>
        </div>
        <NavLink 
          to="/dashboard" 
          className="flex items-center gap-2 px-4 py-2 mt-2 text-white/60 hover:text-white text-sm transition-colors"
        >
          <ChevronLeft size={16} />
          Volver a App
        </NavLink>
      </div>
    </aside>
  );
}