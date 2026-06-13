import { useState, useEffect } from "react";
import { useAuditoria } from "@/hooks/useAuditoria";
import { useAdminAuth } from "@/hooks/admin/useAdminAuth";
import {
  Search,
  Filter,
  Download,
  User,
  Calendar,
  Activity,
  ChevronDown,
  ChevronUp,
  Eye,
} from "lucide-react";

const ACCIONES = [
  { value: "", label: "Todas las acciones" },
  { value: "crear_empleado", label: "Crear Empleado" },
  { value: "cambiar_rol", label: "Cambiar Rol" },
  { value: "activar", label: "Activar" },
  { value: "desactivar", label: "Desactivar" },
  { value: "login", label: "Inicio de Sesion" },
  { value: "logout", label: "Cierre de Sesion" },
  { value: "crear_paciente", label: "Crear Paciente" },
  { value: "crear_cita", label: "Crear Cita" },
  { value: "crear_receta", label: "Crear Receta" },
];

const ENTIDADES = [
  { value: "", label: "Todas las entidades" },
  { value: "empleado", label: "Empleado" },
  { value: "rol", label: "Rol" },
  { value: "paciente", label: "Paciente" },
  { value: "cita", label: "Cita" },
  { value: "receta", label: "Receta" },
  { value: "sistema", label: "Sistema" },
];

export default function AuditoriaPage() {
  useAdminAuth();
  const { logs, loading, error, listarLogs } = useAuditoria();

  const [filtros, setFiltros] = useState({
    accion: "",
    entidad: "",
    usuario_email: "",
    fechaDesde: "",
    fechaHasta: "",
  });

  const [expandedLog, setExpandedLog] = useState<string | null>(null);

  useEffect(() => {
    listarLogs({ limite: 100 });
  }, [listarLogs]);

  const handleBuscar = () => {
    listarLogs({
      ...filtros,
      limite: 500,
    });
  };

  const handleLimpiar = () => {
    setFiltros({
      accion: "",
      entidad: "",
      usuario_email: "",
      fechaDesde: "",
      fechaHasta: "",
    });
    listarLogs({ limite: 100 });
  };

  const handleExportarCSV = () => {
    if (logs.length === 0) return;

    const headers = ["Fecha", "Usuario", "Email", "Accion", "Entidad", "Detalle"];
    const rows = logs.map((log) => [
      new Date(log.created_at).toLocaleString("es-GT"),
      log.usuario_nombre,
      log.usuario_email,
      log.accion,
      log.entidad,
      JSON.stringify(log.detalle),
    ]);

    const csv = [headers, ...rows]
      .map((row) => row.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(","))
      .join("\\n");

    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `auditoria_ezpay_${new Date().toISOString().split("T")[0]}.csv`;
    link.click();
  };

  const getAccionColor = (accion: string) => {
    const colors: Record<string, string> = {
      crear_empleado: "bg-green-100 text-green-700",
      cambiar_rol: "bg-yellow-100 text-yellow-700",
      activar: "bg-emerald-100 text-emerald-700",
      desactivar: "bg-red-100 text-red-700",
      login: "bg-blue-100 text-blue-700",
      logout: "bg-gray-100 text-gray-700",
      crear_paciente: "bg-purple-100 text-purple-700",
      crear_cita: "bg-indigo-100 text-indigo-700",
      crear_receta: "bg-cyan-100 text-cyan-700",
    };
    return colors[accion] || "bg-gray-100 text-gray-700";
  };

  const getAccionLabel = (accion: string) => {
    const found = ACCIONES.find((a) => a.value === accion);
    return found?.label || accion;
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Auditoria y Logs</h1>
          <p className="text-gray-400 mt-1">
            Registro de todas las actividades del sistema
          </p>
        </div>
        <button
          onClick={handleExportarCSV}
          disabled={logs.length === 0}
          className="flex items-center gap-2 px-4 py-2 bg-[#00f2ff] text-black rounded-lg font-medium hover:bg-[#00d4e0] transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <Download className="w-4 h-4" />
          Exportar CSV
        </button>
      </div>

      {/* Filtros */}
      <div className="bg-[#1a1a2e] rounded-xl p-6 border border-gray-800">
        <div className="flex items-center gap-2 mb-4">
          <Filter className="w-5 h-5 text-[#00f2ff]" />
          <h2 className="text-lg font-semibold text-white">Filtros</h2>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-4">
          <div>
            <label className="block text-sm text-gray-400 mb-1">Accion</label>
            <select
              value={filtros.accion}
              onChange={(e) => setFiltros({ ...filtros, accion: e.target.value })}
              className="w-full px-3 py-2 bg-[#0f0f23] border border-gray-700 rounded-lg text-white focus:border-[#00f2ff] focus:outline-none"
            >
              {ACCIONES.map((a) => (
                <option key={a.value} value={a.value}>
                  {a.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Entidad</label>
            <select
              value={filtros.entidad}
              onChange={(e) => setFiltros({ ...filtros, entidad: e.target.value })}
              className="w-full px-3 py-2 bg-[#0f0f23] border border-gray-700 rounded-lg text-white focus:border-[#00f2ff] focus:outline-none"
            >
              {ENTIDADES.map((e) => (
                <option key={e.value} value={e.value}>
                  {e.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Email Usuario</label>
            <input
              type="text"
              value={filtros.usuario_email}
              onChange={(e) => setFiltros({ ...filtros, usuario_email: e.target.value })}
              placeholder="buscar@email.com"
              className="w-full px-3 py-2 bg-[#0f0f23] border border-gray-700 rounded-lg text-white placeholder-gray-500 focus:border-[#00f2ff] focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Desde</label>
            <input
              type="date"
              value={filtros.fechaDesde}
              onChange={(e) => setFiltros({ ...filtros, fechaDesde: e.target.value })}
              className="w-full px-3 py-2 bg-[#0f0f23] border border-gray-700 rounded-lg text-white focus:border-[#00f2ff] focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Hasta</label>
            <input
              type="date"
              value={filtros.fechaHasta}
              onChange={(e) => setFiltros({ ...filtros, fechaHasta: e.target.value })}
              className="w-full px-3 py-2 bg-[#0f0f23] border border-gray-700 rounded-lg text-white focus:border-[#00f2ff] focus:outline-none"
            />
          </div>
        </div>

        <div className="flex gap-3 mt-4">
          <button
            onClick={handleBuscar}
            className="flex items-center gap-2 px-4 py-2 bg-[#00f2ff] text-black rounded-lg font-medium hover:bg-[#00d4e0] transition-colors"
          >
            <Search className="w-4 h-4" />
            Buscar
          </button>
          <button
            onClick={handleLimpiar}
            className="px-4 py-2 border border-gray-600 text-gray-300 rounded-lg hover:bg-gray-800 transition-colors"
          >
            Limpiar
          </button>
        </div>
      </div>

      {/* Tabla de Logs */}
      <div className="bg-[#1a1a2e] rounded-xl border border-gray-800 overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-gray-400">Cargando logs...</div>
        ) : error ? (
          <div className="p-12 text-center text-red-400">{error}</div>
        ) : logs.length === 0 ? (
          <div className="p-12 text-center text-gray-400">
            <Activity className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p>No hay registros de auditoria</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-gray-700 bg-[#0f0f23]">
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">
                    Fecha
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">
                    Usuario
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">
                    Accion
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">
                    Entidad
                  </th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">
                    Detalle
                  </th>
                  <th className="px-4 py-3 text-center text-xs font-medium text-gray-400 uppercase">
                    Ver
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-800">
                {logs.map((log) => (
                  <>
                    <tr
                      key={log.id}
                      className="hover:bg-[#252540] transition-colors cursor-pointer"
                      onClick={() =>
                        setExpandedLog(expandedLog === log.id ? null : log.id)
                      }
                    >
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2 text-sm text-gray-300">
                          <Calendar className="w-4 h-4 text-[#00f2ff]" />
                          {new Date(log.created_at).toLocaleString("es-GT", {
                            day: "2-digit",
                            month: "short",
                            year: "numeric",
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <User className="w-4 h-4 text-gray-400" />
                          <div>
                            <p className="text-sm text-white font-medium">
                              {log.usuario_nombre}
                            </p>
                            <p className="text-xs text-gray-500">{log.usuario_email}</p>
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${getAccionColor(
                            log.accion
                          )}`}
                        >
                          {getAccionLabel(log.accion)}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className="text-sm text-gray-300 capitalize">
                          {log.entidad}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className="text-sm text-gray-400 truncate max-w-[200px] block">
                          {JSON.stringify(log.detalle).substring(0, 50)}...
                        </span>
                      </td>
                      <td className="px-4 py-3 text-center">
                        {expandedLog === log.id ? (
                          <ChevronUp className="w-4 h-4 text-[#00f2ff] mx-auto" />
                        ) : (
                          <ChevronDown className="w-4 h-4 text-gray-400 mx-auto" />
                        )}
                      </td>
                    </tr>

                    {expandedLog === log.id && (
                      <tr className="bg-[#0f0f23]">
                        <td colSpan={6} className="px-4 py-4">
                          <div className="border-l-2 border-[#00f2ff] pl-4 space-y-3">
                            <div className="flex items-center gap-2 text-[#00f2ff]">
                              <Eye className="w-4 h-4" />
                              <span className="font-medium">Detalle completo</span>
                            </div>

                            <div className="grid grid-cols-2 gap-4 text-sm">
                              <div>
                                <p className="text-gray-500">ID del Log</p>
                                <p className="text-white font-mono">{log.id}</p>
                              </div>
                              <div>
                                <p className="text-gray-500">ID Entidad</p>
                                <p className="text-white font-mono">
                                  {log.entidad_id || "N/A"}
                                </p>
                              </div>
                              <div>
                                <p className="text-gray-500">IP Address</p>
                                <p className="text-white font-mono">
                                  {log.ip_address || "N/A"}
                                </p>
                              </div>
                              <div>
                                <p className="text-gray-500">User Agent</p>
                                <p className="text-white font-mono truncate">
                                  {log.user_agent || "N/A"}
                                </p>
                              </div>
                            </div>

                            <div>
                              <p className="text-gray-500 text-sm mb-1">Datos JSON:</p>
                              <pre className="bg-[#1a1a2e] p-3 rounded-lg text-xs text-gray-300 overflow-x-auto">
                                {JSON.stringify(log.detalle, null, 2)}
                              </pre>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Resumen */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="bg-[#1a1a2e] rounded-xl p-4 border border-gray-800">
          <p className="text-gray-400 text-sm">Total Logs</p>
          <p className="text-2xl font-bold text-white">{logs.length}</p>
        </div>
        <div className="bg-[#1a1a2e] rounded-xl p-4 border border-gray-800">
          <p className="text-gray-400 text-sm">Acciones Unicas</p>
          <p className="text-2xl font-bold text-[#00f2ff]">
            {new Set(logs.map((l) => l.accion)).size}
          </p>
        </div>
        <div className="bg-[#1a1a2e] rounded-xl p-4 border border-gray-800">
          <p className="text-gray-400 text-sm">Usuarios Activos</p>
          <p className="text-2xl font-bold text-green-400">
            {new Set(logs.map((l) => l.usuario_email)).size}
          </p>
        </div>
        <div className="bg-[#1a1a2e] rounded-xl p-4 border border-gray-800">
          <p className="text-gray-400 text-sm">Ultima Actividad</p>
          <p className="text-lg font-bold text-white">
            {logs[0]
              ? new Date(logs[0].created_at).toLocaleTimeString("es-GT", {
                  hour: "2-digit",
                  minute: "2-digit",
                })
              : "--:--"}
          </p>
        </div>
      </div>
    </div>
  );
}