import { useState, useEffect } from "react";
import { useNotificaciones } from "@/hooks/useNotificaciones";
import { useAuth } from "@/hooks/useAuth";
import {
  Bell,
  Check,
  CheckCheck,
  Calendar,
  DollarSign,
  UserPlus,
  Info,
  Trash2,
  Filter,
} from "lucide-react";

const TIPO_COLORES: Record<string, string> = {
  cita: "bg-blue-100 text-blue-700",
  pago: "bg-green-100 text-green-700",
  empleado: "bg-purple-100 text-purple-700",
  sistema: "bg-gray-100 text-gray-700",
};

const TIPO_ICONOS: Record<string, any> = {
  cita: Calendar,
  pago: DollarSign,
  empleado: UserPlus,
  sistema: Info,
};

export default function NotificacionesPage() {
  const { user } = useAuth();
  const {
    notificaciones,
    noLeidas,
    loading,
    listarNotificaciones,
    marcarLeida,
    marcarTodasLeidas,
  } = useNotificaciones({ realtime: true });

  const [filtroTipo, setFiltroTipo] = useState("");

  useEffect(() => {
    listarNotificaciones();
  }, [listarNotificaciones]);

  const notificacionesFiltradas = filtroTipo
    ? notificaciones.filter((n) => n.tipo === filtroTipo)
    : notificaciones;

  return (
    <div className="p-6 max-w-4xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <Bell className="w-6 h-6 text-[#00f2ff]" />
            Notificaciones
          </h1>
          <p className="text-gray-400 mt-1">
            {noLeidas > 0
              ? `Tienes ${noLeidas} notificación${noLeidas > 1 ? "es" : ""} sin leer`
              : "No tienes notificaciones pendientes"}
          </p>
        </div>
        <div className="flex gap-2">
          <select
            value={filtroTipo}
            onChange={(e) => setFiltroTipo(e.target.value)}
            className="px-3 py-2 bg-[#1a1a2e] border border-gray-700 rounded-lg text-white text-sm"
          >
            <option value="">Todos los tipos</option>
            <option value="cita">Citas</option>
            <option value="pago">Pagos</option>
            <option value="empleado">Empleados</option>
            <option value="sistema">Sistema</option>
          </select>
          {noLeidas > 0 && (
            <button
              onClick={marcarTodasLeidas}
              className="flex items-center gap-2 px-4 py-2 bg-[#00f2ff] text-black rounded-lg text-sm font-medium hover:bg-[#00d4e0]"
            >
              <CheckCheck className="w-4 h-4" />
              Marcar todas leídas
            </button>
          )}
        </div>
      </div>

      {/* Lista */}
      <div className="space-y-3">
        {loading ? (
          <div className="text-center py-12 text-gray-400">Cargando notificaciones...</div>
        ) : notificacionesFiltradas.length === 0 ? (
          <div className="text-center py-12 text-gray-400">
            <Bell className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No hay notificaciones</p>
          </div>
        ) : (
          notificacionesFiltradas.map((notif) => {
            const Icon = TIPO_ICONOS[notif.tipo] || Info;
            return (
              <div
                key={notif.id}
                className={`flex items-start gap-4 p-4 rounded-xl border transition-all ${
                  notif.leida
                    ? "bg-[#0f0f23] border-gray-800 opacity-60"
                    : "bg-[#1a1a2e] border-[#00f2ff]/30"
                }`}
              >
                <div
                  className={`p-2 rounded-lg ${TIPO_COLORES[notif.tipo] || "bg-gray-100"}`}
                >
                  <Icon className="w-5 h-5" />
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <h3 className="text-white font-medium text-sm">{notif.titulo}</h3>
                    {!notif.leida && (
                      <span className="w-2 h-2 bg-[#00f2ff] rounded-full" />
                    )}
                  </div>
                  <p className="text-gray-400 text-sm">{notif.mensaje}</p>
                  <p className="text-gray-600 text-xs mt-1">
                    {new Date(notif.created_at).toLocaleString("es-GT", {
                      day: "2-digit",
                      month: "short",
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </p>
                </div>

                {!notif.leida && (
                  <button
                    onClick={() => marcarLeida(notif.id)}
                    className="p-2 text-gray-400 hover:text-[#00f2ff] hover:bg-[#00f2ff]/10 rounded-lg transition-colors"
                    title="Marcar como leída"
                  >
                    <Check className="w-4 h-4" />
                  </button>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}