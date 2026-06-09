import { UserCheck } from 'lucide-react';
import { Users } from 'lucide-react';
import { ClipboardCheck } from 'lucide-react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { usePaisActivo } from '@/hooks/usePaisActivo';
import { 
  LayoutDashboard, 
  Globe, 
  Layers, 
  Stethoscope, 
  Building, 
  FlaskConical, 
  Car,
  Pill,
  Store,
  Megaphone,
  Handshake,
  AlertCircle,
  DollarSign,
  BarChart3,
  Shield,
  ChevronLeft,
  LogOut,
  Activity,
  BarChart4,
  MapPin,
  ArrowLeftRight
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/lib/supabase';

export function SidebarAdmin() {
  const navigate = useNavigate();
  const location = useLocation();
  const { adminUser } = useAdminAuth();
  const { paisActivo, clearPaisActivo } = usePaisActivo();

  // Detectar si estamos en modo "país activo"
  const enModoPais = location.pathname.startsWith('/admin-ezpay/pais/');
  const paisIdMatch = location.pathname.match(/^\/admin-ezpay\/pais\/([^/]+)/);
  const paisIdActual = paisIdMatch ? paisIdMatch[1] : null;

  const menuItemsBase = [
    { path: '/admin-ezpay/asignacion-roles', icon: UserCheck, label: 'Asignar Roles' },
    { path: '/admin-ezpay/usuarios', icon: Users, label: 'Usuarios' },
    { path: '/admin-ezpay', icon: LayoutDashboard, label: 'Dashboard' },
    { path: '/admin-ezpay/paises', icon: Globe, label: 'Países' },
  ];

  const menuItemsPais = paisIdActual ? [
    { path: `/admin-ezpay/pais/${paisIdActual}`, icon: LayoutDashboard, label: 'Dashboard País' },
    { path: '/admin-ezpay/planes-todos', icon: Layers, label: 'Todos los Planes' },
    { path: '/admin-ezpay/planes-medico', icon: Stethoscope, label: 'Planes Médico' },
    { path: '/admin-ezpay/planes-clinica', icon: Building, label: 'Planes Clínica' },
    { path: '/admin-ezpay/planes-lab', icon: FlaskConical, label: 'Planes Lab/Farmacia' },
    { path: '/admin-ezpay/planes-visitador', icon: Car, label: 'Planes Visitador' },
    { path: '/admin-ezpay/planes-farmaceutico', icon: Pill, label: 'Planes Farmacéutico' },
    { path: '/admin-ezpay/planes-farmacia', icon: Store, label: 'Planes Farmacia' },
    { path: '/admin-ezpay/planes-publicidad-config', icon: Megaphone, label: 'Planes Publicidad' },
    { path: '/admin-ezpay/planes-empresas-afines', icon: Handshake, label: 'Empresas Afines' },
    { path: '/admin-ezpay/excepciones', icon: AlertCircle, label: 'Excepciones' },
    { path: '/admin-ezpay/finanzas', icon: DollarSign, label: 'Finanzas' },
    { path: '/admin-ezpay/reportes', icon: BarChart3, label: 'Reportes EZPay' },
    { path: '/admin-ezpay/reportes-ezpay-v2', icon: BarChart4, label: 'Reportes EZPay V2' },
    { path: '/admin-ezpay/roles', icon: Shield, label: 'Roles' },
    { path: '/admin-ezpay/solicitudes-campana', icon: ClipboardCheck, label: 'Solicitudes Campaña' },
    { path: '/admin-ezpay/pagos-proveedores', icon: DollarSign, label: 'Pagos Proveedores' },
    { path: '/admin-ezpay/empresas-proveedoras', icon: Building, label: 'Empresas Proveedoras' },
    { path: '/admin-ezpay/auditoria', icon: Activity, label: 'Auditoría' },
  ] : [];

  const menuItems = enModoPais ? menuItemsPais : menuItemsBase;

  const isActive = (path: string) => {
    if (path === '/admin-ezpay') {
      return location.pathname === '/admin-ezpay';
    }
    return location.pathname.startsWith(path);
  };

  const handleCambiarPais = () => {
    clearPaisActivo();
    navigate('/admin-ezpay/paises');
  };

  return (
    <aside className="w-64 bg-[#1E5C8E] text-white flex flex-col h-screen fixed left-0 top-0 z-40">
      <div className="p-6 border-b border-white/10">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-white/10 rounded-lg flex items-center justify-center">
            <span className="text-xl font-bold">E</span>
          </div>
          <div>
            <h1 className="font-bold text-lg leading-tight">EZPayConnect</h1>
            <p className="text-xs text-white/60">Panel Maestro</p>
          </div>
        </div>
      </div>

      {/* Indicador de País Activo */}
      {enModoPais && paisActivo && (
        <div className="mx-3 mt-3 p-3 bg-white/10 rounded-lg">
          <div className="flex items-center gap-2 mb-1">
            <MapPin className="w-4 h-4 text-[#87CEEB]" />
            <span className="text-xs text-white/70">Administrando</span>
          </div>
          <p className="text-sm font-bold">{paisActivo.nombre}</p>
          <p className="text-xs text-white/60">{paisActivo.codigo} · {paisActivo.moneda}</p>
          <Button
            variant="ghost"
            size="sm"
            className="w-full mt-2 justify-start text-white/70 hover:text-white hover:bg-white/10 px-2 h-7 text-xs"
            onClick={handleCambiarPais}
          >
            <ArrowLeftRight className="w-3 h-3 mr-1" />
            Cambiar País
          </Button>
        </div>
      )}

      <nav className="flex-1 overflow-y-auto py-4 px-3 space-y-1">
        {menuItems.map((item) => {
          const Icon = item.icon;
          const active = isActive(item.path);
          return (
            <button
              key={item.path}
              onClick={() => navigate(item.path)}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all ${
                active
                  ? 'bg-white text-[#1E5C8E] shadow-sm'
                  : 'text-white/80 hover:bg-white/10 hover:text-white'
              }`}
            >
              <Icon className="w-5 h-5" />
              <span>{item.label}</span>
            </button>
          );
        })}
      </nav>

      <div className="p-4 border-t border-white/10 space-y-3">
        {adminUser && (
          <div className="px-3 py-2 bg-white/10 rounded-lg">
            <p className="text-sm font-medium">{adminUser.nombre}</p>
            <p className="text-xs text-white/60 capitalize">{adminUser.rol.replace('_', ' ')}</p>
          </div>
        )}
        <Button
          variant="ghost"
          className="w-full justify-start text-white/80 hover:text-white hover:bg-white/10"
          onClick={() => navigate('/dashboard')}
        >
          <ChevronLeft className="w-4 h-4 mr-2" />
          Volver al Dashboard
        </Button>
        <Button
          variant="ghost"
          className="w-full justify-start text-white/80 hover:text-white hover:bg-white/10"
          onClick={async () => {
            await supabase.auth.signOut();
            navigate('/login');
          }}
        >
          <LogOut className="w-4 h-4 mr-2" />
          Cerrar Sesión
        </Button>
      </div>
    </aside>
  );
}
