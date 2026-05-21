// ============================================
// Página: Ventas de Planes (Panel Admin)
// Permite al admin registrar ventas de planes
// ============================================

import { useState, useEffect } from "react";
import { useVentas } from "@/hooks/admin/useVentas";
import { useAdminAuth } from "@/hooks/admin/useAdminAuth";
import {
  ShoppingCart,
  Plus,
  Search,
  DollarSign,
  Calendar,
  Globe,
  User,
  Package,
  CheckCircle2,
  AlertCircle,
  RefreshCw,
} from "lucide-react";

export default function VentasPage() {
  const { adminUser } = useAdminAuth();
  const {
    clientes,
    planesBase,
    planesConfig,
    paises,
    ventas,
    loading,
    saving,
    cargarConfiguraciones,
    registrarVenta,
    recargar,
  } = useVentas();

  const [step, setStep] = useState(1);
  const [selectedCliente, setSelectedCliente] = useState("");
  const [selectedPais, setSelectedPais] = useState("");
  const [selectedPlan, setSelectedPlan] = useState("");
  const [selectedConfig, setSelectedConfig] = useState("");
  const [fechaInicio, setFechaInicio] = useState("");
  const [fechaFin, setFechaFin] = useState("");
  const [tipoCiclo, setTipoCiclo] = useState("mensual");
  const [searchCliente, setSearchCliente] = useState("");
  const [showClientes, setShowClientes] = useState(false); // NUEVO: controlar dropdown
  const [success, setSuccess] = useState(false);

  // Cargar configuraciones cuando cambia país o plan
  useEffect(() => {
    if (selectedPais && selectedPlan) {
      cargarConfiguraciones(selectedPais, selectedPlan);
    }
  }, [selectedPais, selectedPlan, cargarConfiguraciones]);

  // Calcular fecha fin automáticamente
  useEffect(() => {
    if (fechaInicio && tipoCiclo) {
      const inicio = new Date(fechaInicio);
      const fin = new Date(inicio);
      if (tipoCiclo === "mensual") fin.setMonth(fin.getMonth() + 1);
      else if (tipoCiclo === "anual") fin.setFullYear(fin.getFullYear() + 1);
      else if (tipoCiclo === "trimestral") fin.setMonth(fin.getMonth() + 3);
      setFechaFin(fin.toISOString().split("T")[0]);
    }
  }, [fechaInicio, tipoCiclo]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedConfig) return;

    const config = planesConfig.find((c) => c.id === selectedConfig);
    if (!config) return;

    const result = await registrarVenta({
      medico_id: selectedCliente,
      plan_config_id: selectedConfig,
      fecha_inicio: fechaInicio,
      fecha_fin: fechaFin,
      tipo_ciclo: tipoCiclo,
      precio_aplicado: config.precio_local,
      moneda: paises.find((p) => p.id === selectedPais)?.moneda_local || "USD",
    });

    if (result.success) {
      setSuccess(true);
      setTimeout(() => setSuccess(false), 3000);
      // Reset form
      setStep(1);
      setSelectedCliente("");
      setSelectedPais("");
      setSelectedPlan("");
      setSelectedConfig("");
      setFechaInicio("");
      setFechaFin("");
      setSearchCliente("");
      setShowClientes(false);
    }
  };

  const clientesFiltrados = clientes.filter((c) =>
    c.nombre_completo.toLowerCase().includes(searchCliente.toLowerCase()) ||
    c.email.toLowerCase().includes(searchCliente.toLowerCase())
  );

  const configSeleccionada = planesConfig.find((c) => c.id === selectedConfig);
  const paisSeleccionado = paises.find((p) => p.id === selectedPais);
  const planSeleccionado = planesBase.find((p) => p.id === selectedPlan);
  const clienteSeleccionado = clientes.find((c) => c.id === selectedCliente);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#1E5C8E]" />
      </div>
    );
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
            <ShoppingCart className="text-[#1E5C8E]" />
            Ventas de Planes
          </h1>
          <p className="text-gray-500 mt-1">
            Registra ventas y asignaciones de planes a clientes
          </p>
        </div>
        <button
          onClick={recargar}
          className="p-2 text-gray-500 hover:text-[#1E5C8E] hover:bg-blue-50 rounded-lg transition-colors"
          title="Recargar"
        >
          <RefreshCw size={20} />
        </button>
      </div>

      {/* Success message */}
      {success && (
        <div className="mb-4 p-4 bg-green-50 border border-green-200 rounded-xl flex items-center gap-2 text-green-700">
          <CheckCircle2 size={20} />
          <span>Venta registrada exitosamente. Notificación enviada al admin.</span>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Formulario de Venta */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center gap-2">
            <Plus size={20} className="text-[#1E5C8E]" />
            Nueva Venta
          </h2>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Step 1: Cliente - CORREGIDO */}
            <div className="relative">
              <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                <User size={14} />
                Cliente *
              </label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={16} />
                <input
                  type="text"
                  placeholder="Escribe para buscar cliente..."
                  value={searchCliente}
                  onChange={(e) => {
                    setSearchCliente(e.target.value);
                    setSelectedCliente(""); // Limpiar selección al escribir
                    setShowClientes(true); // Mostrar dropdown al escribir
                  }}
                  onFocus={() => setShowClientes(true)}
                  className="w-full pl-9 pr-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB]"
                />
              </div>
              
              {/* Lista de resultados - CON CONTROL DE VISIBILIDAD */}
              {showClientes && searchCliente.length > 0 && clientesFiltrados.length > 0 && (
                <div className="absolute z-50 w-full mt-1 bg-white border border-gray-200 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                  <div className="p-2 text-xs text-gray-500 border-b border-gray-100 flex items-center justify-between">
                    <span>{clientesFiltrados.length} resultado(s) encontrado(s)</span>
                    <button 
                      type="button"
                      onClick={() => setShowClientes(false)}
                      className="text-gray-400 hover:text-gray-600 px-2"
                    >
                      ✕
                    </button>
                  </div>
                  {clientesFiltrados.map((cliente) => (
                    <div
                      key={cliente.id}
                      onClick={() => {
                        setSelectedCliente(cliente.id);
                        setSearchCliente(cliente.nombre_completo);
                        setShowClientes(false); // CERRAR DROPDOWN AL SELECCIONAR
                      }}
                      className={`p-3 cursor-pointer hover:bg-blue-50 transition-colors border-b border-gray-50 last:border-0 ${
                        selectedCliente === cliente.id ? "bg-blue-50 border-l-4 border-[#1E5C8E]" : ""
                      }`}
                    >
                      <p className="text-sm font-medium text-gray-800">{cliente.nombre_completo}</p>
                      <p className="text-xs text-gray-500">{cliente.email} • <span className="capitalize">{cliente.rol}</span></p>
                    </div>
                  ))}
                </div>
              )}
              
              {showClientes && searchCliente.length > 0 && clientesFiltrados.length === 0 && (
                <div className="absolute z-50 w-full mt-1 p-3 bg-gray-50 border border-gray-200 rounded-lg text-sm text-gray-500 flex items-center justify-between">
                  <span>No se encontraron clientes con "{searchCliente}"</span>
                  <button 
                    type="button"
                    onClick={() => setShowClientes(false)}
                    className="text-gray-400 hover:text-gray-600 px-2"
                  >
                    ✕
                  </button>
                </div>
              )}
              
              {selectedCliente && (
                <div className="mt-2 p-2 bg-green-50 border border-green-200 rounded-lg flex items-center gap-2">
                  <CheckCircle2 size={16} className="text-green-600" />
                  <span className="text-sm text-green-700">
                    Cliente seleccionado: <strong>{clientes.find(c => c.id === selectedCliente)?.nombre_completo}</strong>
                  </span>
                  <button 
                    type="button"
                    onClick={() => {
                      setSelectedCliente("");
                      setSearchCliente("");
                      setShowClientes(false);
                    }}
                    className="ml-auto text-green-600 hover:text-green-800 px-2"
                  >
                    ✕
                  </button>
                </div>
              )}
            </div>

            {/* Step 2: País */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                <Globe size={14} />
                País
              </label>
              <select
                value={selectedPais}
                onChange={(e) => {
                  setSelectedPais(e.target.value);
                  setSelectedConfig("");
                }}
                className="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB]"
              >
                <option value="">Seleccionar país</option>
                {paises.map((pais) => (
                  <option key={pais.id} value={pais.id}>
                    {pais.nombre} ({pais.moneda_local})
                  </option>
                ))}
              </select>
            </div>

            {/* Step 3: Plan Base */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                <Package size={14} />
                Plan Base
              </label>
              <select
                value={selectedPlan}
                onChange={(e) => {
                  setSelectedPlan(e.target.value);
                  setSelectedConfig("");
                }}
                className="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB]"
              >
                <option value="">Seleccionar plan</option>
                {planesBase.map((plan) => (
                  <option key={plan.id} value={plan.id}>
                    {plan.nombre} - {plan.descripcion?.substring(0, 50)}...
                  </option>
                ))}
              </select>
            </div>

                        {/* Step 4: Configuración */}
            {selectedPais && selectedPlan && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  <DollarSign size={14} />
                  Configuración y Precio
                </label>
                
                {planesConfig.length === 0 ? (
                  <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
                    <p className="text-sm text-yellow-800 font-medium">
                      ⚠️ No hay configuración de precio para este plan en {paisSeleccionado?.nombre}
                    </p>
                    <p className="text-xs text-yellow-600 mt-1">
                      Debes crear una configuración en el panel de planes primero.
                    </p>
                  </div>
                ) : (
                  <div className="space-y-2">
                    {planesConfig.map((config) => {
                      const precioFinal = config.precio_local * (1 - config.descuento_porcentaje / 100);
                      return (
                        <div
                          key={config.id}
                          onClick={() => setSelectedConfig(config.id)}
                          className={`p-3 border rounded-lg cursor-pointer transition-colors ${
                            selectedConfig === config.id
                              ? "border-[#1E5C8E] bg-blue-50"
                              : "border-gray-200 hover:border-gray-300"
                          }`}
                        >
                          <div className="flex items-center justify-between">
                            <div>
                              <p className="text-sm font-medium text-gray-800">
                                Precio: {config.precio_local} {paisSeleccionado?.moneda_local}
                              </p>
                              {config.descuento_porcentaje > 0 && (
                                <p className="text-xs text-green-600">
                                  Descuento: {config.descuento_porcentaje}% → Final: {precioFinal.toFixed(2)}
                                </p>
                              )}
                              <p className="text-xs text-gray-500">
                                Comisión: {config.comision_aplicada}% • Anual: {config.precio_anual}
                              </p>
                            </div>
                            {selectedConfig === config.id && (
                              <CheckCircle2 size={20} className="text-[#1E5C8E]" />
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            )}

            {/* Step 5: Fechas */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  <Calendar size={14} />
                  Fecha Inicio
                </label>
                <input
                  type="date"
                  value={fechaInicio}
                  onChange={(e) => setFechaInicio(e.target.value)}
                  className="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB]"
                  required
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Tipo Ciclo
                </label>
                <select
                  value={tipoCiclo}
                  onChange={(e) => setTipoCiclo(e.target.value)}
                  className="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#87CEEB]"
                >
                  <option value="mensual">Mensual</option>
                  <option value="trimestral">Trimestral</option>
                  <option value="anual">Anual</option>
                </select>
              </div>
            </div>

            {fechaFin && (
              <p className="text-sm text-gray-500">
                Fecha fin calculada: <span className="font-medium text-gray-700">{fechaFin}</span>
              </p>
            )}

            {/* Resumen */}
            {configSeleccionada && clienteSeleccionado && (
              <div className="p-4 bg-gray-50 rounded-lg border border-gray-200">
                <h3 className="text-sm font-semibold text-gray-800 mb-2">Resumen de venta</h3>
                <div className="space-y-1 text-sm">
                  <p><span className="text-gray-500">Cliente:</span> {clienteSeleccionado.nombre_completo}</p>
                  <p><span className="text-gray-500">Plan:</span> {planSeleccionado?.nombre}</p>
                  <p><span className="text-gray-500">País:</span> {paisSeleccionado?.nombre}</p>
                  <p><span className="text-gray-500">Precio:</span> {configSeleccionada.precio_local} {paisSeleccionado?.moneda_local}</p>
                  <p><span className="text-gray-500">Período:</span> {fechaInicio} → {fechaFin}</p>
                </div>
              </div>
            )}

            {/* Submit */}
            <button
              type="submit"
              disabled={saving || !selectedCliente || !selectedConfig || !fechaInicio}
              className="w-full py-3 bg-[#1E5C8E] text-white rounded-lg font-medium hover:bg-[#164a73] transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {saving ? (
                <>
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white" />
                  Registrando...
                </>
              ) : (
                <>
                  <ShoppingCart size={18} />
                  Registrar Venta
                </>
              )}
            </button>
          </form>
        </div>

        {/* Lista de Ventas Recientes */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-semibold text-gray-800 mb-4 flex items-center gap-2">
            <DollarSign size={20} className="text-[#1E5C8E]" />
            Ventas Recientes
          </h2>

          {ventas.length === 0 ? (
            <div className="text-center py-8 text-gray-400">
              <AlertCircle size={48} className="mx-auto mb-2" />
              <p>No hay ventas registradas</p>
            </div>
          ) : (
            <div className="space-y-3 max-h-[600px] overflow-y-auto">
              {ventas.map((venta) => (
                <div
                  key={venta.id}
                  className="p-3 border border-gray-100 rounded-lg hover:border-gray-200 transition-colors"
                >
                  <div className="flex items-center justify-between mb-1">
                    <span className={`text-xs px-2 py-0.5 rounded ${
                      venta.estado === "activo"
                        ? "bg-green-100 text-green-700"
                        : "bg-gray-100 text-gray-600"
                    }`}>
                      {venta.estado}
                    </span>
                    <span className="text-xs text-gray-400">
                      {new Date(venta.created_at).toLocaleDateString("es-GT")}
                    </span>
                  </div>
                  <p className="text-sm font-medium text-gray-800">
                    {venta.precio_aplicado} {venta.moneda}
                  </p>
                  <p className="text-xs text-gray-500">
                    {venta.tipo_ciclo} • {venta.fecha_inicio?.substring(0, 10)} → {venta.fecha_fin?.substring(0, 10)}
                  </p>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}