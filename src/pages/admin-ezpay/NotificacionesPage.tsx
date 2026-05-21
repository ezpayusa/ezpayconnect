// ============================================
// Página: Notificaciones Admin EZPay
// Listado completo con filtros y gestión de estados
// ============================================

import { useEffect, useState } from "react";
import { useNotificacionesAdmin } from "@/hooks/admin/useNotificacionesAdmin";
import { useAdminAuth } from "@/hooks/admin/useAdminAuth";
import { Clock, CheckCircle2, Filter, Bell, Archive } from "lucide-react";

export default function NotificacionesAdminPage() {
  const { adminUser } = useAdminAuth();
  const {
    notificaciones,
    noLeidas,
    pendientes,
    loading,
    listarNotificaciones,
    marcarLeida,
    marcarEnProceso,
    marcarCompletada,
    marcarTodasLeidas,
  } = useNotificacionesAdmin();

  const [filtroEstado, setFiltroEstado] = useState<string>("todas");
  const [filtroTipo, setFiltroTipo] = useState<string>("todas");

  useEffect(() => {
    listarNotificaciones();
  }, [listarNotificaciones]);

  const notificacionesFiltradas = notificaciones.filter((n) => {
    const matchEstado = filtroEstado === "todas" || n.estado === filtroEstado;
    const matchTipo = filtroTipo === "todas" || n.tipo === filtroTipo;
    return matchEstado && matchTipo;
  });

  const getTipoColor = (tipo: string) => {
    const colors: Record<string, string> = {
      empleado: "bg-purple-500",
      venta: "bg-green-500",
      plan: "bg-blue-500",
      reporte: "bg-orange-500",
    };
    return colors[tipo] || "bg-gray-500";
  };

  const getEstadoBadge = (estado: string) => {
    const badges: Record<string, { text: string; class: string }> = {
      pendiente: {
        text: "Pendiente",
        class: "bg-red-100 text-red-700 border-red-200",
      },
      en_proceso: {
        text: "En proceso",
        class: "bg-yellow-100 text-yellow-700 border-yellow-200",
      },
      completada: {
        text: "Completada",
        class: "bg-green-100 text-green-700 border-green-200",
      },
      archivada: {
        text: "Archivada",
        class: "bg-gray-100 text-gray-500 border-gray-200",
      },
    };
    return badges[estado] || { text: estado, class: "bg-gray-100 text-gray-700" };
  };

  const esRolDirecto = (notif: any) => {
    return notif.rol_destinatario === adminUser?.rol && notif.estado === "pendiente";
  };

  const esRolDirectoEnProceso = (notif: any) => {
    return notif.rol_destinatario === adminUser?.rol && notif.estado === "en_proceso";
  };

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
            <Bell className="text-[#1E5C8E]" />
            Notificaciones
          </h1>
          <p className="text-gray-500 mt-1">
            {pendientes > 0
              ? `${pendientes} notificaciones pendientes de atención`
              : "Sin notificaciones pendientes"}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {noLeidas > 0 && (
            <button
              onClick={marcarTodasLeidas}
              className="px-4 py-2 bg-[#1E5C8E] text-white rounded-lg text-sm hover:bg-[#164a73] transition-colors flex items-center gap-2"
            >
              <CheckCircle2 size={16} />
              Marcar todas leídas
            </button>
          )}
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        <div className="bg-white p-4 rounded-xl border border-gray-200">
          <p className="text-sm text-gray-500">Total</p>
          <p className="text-2xl font-bold text-gray-800">{notificaciones.length}</p>
        </div>
        <div className="bg-white p-4 rounded-xl border border-red-200">
          <p className="text-sm text-red-600">Pendientes</p>
          <p className="text-2xl font-bold text-red-700">
            {notificaciones.filter((n) => n.estado === "pendiente").length}
          </p>
        </div>
        <div className="bg-white p-4 rounded-xl border border-yellow-200">
          <p className="text-sm text-yellow-600">En proceso</p>
          <p className="text-2xl font-bold text-yellow-700">
            {notificaciones.filter((n) => n.estado === "en_proceso").length}
          </p>
        </div>
        <div className="bg-white p-4 rounded-xl border border-green-200">
          <p className="text-sm text-green-600">Completadas</p>
          <p className="text-2xl font-bold text-green-700">
            {notificaciones.filter((n) => n.estado === "completada").length}
          </p>
        </div>
      </div>

      {/* Filtros */}
      <div className="flex items-center gap-4 mb-6 bg-white p-4 rounded-xl border border-gray-200">
        <Filter size={18} className="text-gray-400" />
        <div className="flex items-center gap-2">
          <label className="text-sm text-gray-600">Estado:</label>
          <select
            value={filtroEstado}
            onChange={(e) => setFiltroEstado(e.target.value)}
            className="px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB]"
          >
            <option value="todas">Todos</option>
            <option value="pendiente">Pendiente</option>
            <option value="en_proceso">En proceso</option>
            <option value="completada">Completada</option>
          </select>
        </div>
        <div className="flex items-center gap-2">
          <label className="text-sm text-gray-600">Tipo:</label>
          <select
            value={filtroTipo}
            onChange={(e) => setFiltroTipo(e.target.value)}
            className="px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB]"
          >
            <option value="todas">Todos</option>
            <option value="empleado">Empleado</option>
            <option value="venta">Venta</option>
            <option value="plan">Plan</option>
            <option value="reporte">Reporte</option>
          </select>
        </div>
      </div>

      {/* Lista */}
      {loading ? (
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[#1E5C8E]" />
        </div>
      ) : notificacionesFiltradas.length === 0 ? (
        <div className="text-center py-12 bg-white rounded-xl border border-gray-200">
          <Archive size={48} className="mx-auto text-gray-300 mb-4" />
          <p className="text-gray-500">No hay notificaciones con los filtros seleccionados</p>
        </div>
      ) : (
        <div className="space-y-3">
          {notificacionesFiltradas.map((notif) => {
            const estadoBadge = getEstadoBadge(notif.estado);
            const puedeEnProceso = esRolDirecto(notif);
            const puedeCompletar = esRolDirectoEnProceso(notif);

            return (
              <div
                key={notif.id}
                className={`bg-white p-4 rounded-xl border transition-all hover:shadow-md ${
                  !notif.leida ? "border-[#87CEEB]" : "border-gray-200"
                }`}
              >
                <div className="flex items-start justify-between gap-4">
                  <div className="flex items-start gap-3 flex-1">
                    <div
                      className={`w-3 h-3 rounded-full mt-1.5 flex-shrink-0 ${getTipoColor(
                        notif.tipo
                      )}`}
                    />
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <h3 className="font-semibold text-gray-800">
                          {notif.titulo}
                        </h3>
                        <span
                          className={`text-xs px-2 py-0.5 rounded border ${estadoBadge.class}`}
                        >
                          {estadoBadge.text}
                        </span>
                        {notif.metadata?.es_seguimiento && (
                          <span className="text-xs px-2 py-0.5 rounded bg-gray-100 text-gray-600 border border-gray-200">
                            Seguimiento
                          </span>
                        )}
                      </div>
                      <p className="text-sm text-gray-600 mb-2">{notif.mensaje}</p>
                      <div className="flex items-center gap-4 text-xs text-gray-400">
                        <span>
                          {new Date(notif.created_at).toLocaleString("es-GT", {
                            day: "2-digit",
                            month: "long",
                            year: "numeric",
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </span>
                        <span className="capitalize">Tipo: {notif.tipo}</span>
                        <span>Rol: {notif.rol_destinatario}</span>
                      </div>
                    </div>
                  </div>

                  {/* Acciones */}
                  <div className="flex items-center gap-2 flex-shrink-0">
                    {!notif.leida && (
                      <button
                        onClick={() => marcarLeida(notif.id)}
                        className="p-2 text-gray-400 hover:text-[#1E5C8E] hover:bg-blue-50 rounded-lg transition-colors"
                        title="Marcar como leída"
                      >
                        <Bell size={16} />
                      </button>
                    )}

                    {puedeEnProceso && (
                      <button
                        onClick={() => marcarEnProceso(notif.id)}
                        className="px-3 py-1.5 bg-yellow-50 text-yellow-700 rounded-lg text-xs hover:bg-yellow-100 transition-colors flex items-center gap-1"
                      >
                        <Clock size={14} />
                        En proceso
                      </button>
                    )}

                    {puedeCompletar && (
                      <button
                        onClick={() => marcarCompletada(notif.id, notif.evento_id)}
                        className="px-3 py-1.5 bg-green-50 text-green-700 rounded-lg text-xs hover:bg-green-100 transition-colors flex items-center gap-1"
                      >
                        <CheckCircle2 size={14} />
                        Completar
                      </button>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}