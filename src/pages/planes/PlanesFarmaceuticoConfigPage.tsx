import { useState } from "react";
import { usePlanes } from "@/hooks/usePlanes";
import { usePaisFiltro } from "@/hooks/usePaisFiltro";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
  SheetClose,
} from "@/components/ui/sheet";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Trash2, Edit, Plus, ArrowLeft, X } from "lucide-react";
import { useNavigate } from "react-router-dom";
import type { PlanBase } from "@/types/planes";

// Monedas latinoamericanas + España/USA/Canadá
const MONEDAS_LATAM = [
  { codigo: "GTQ", nombre: "Guatemala — Quetzal", simbolo: "Q" },
  { codigo: "USD", nombre: "Estados Unidos / Panamá / Ecuador — Dólar", simbolo: "$" },
  { codigo: "HNL", nombre: "Honduras — Lempira", simbolo: "L" },
  { codigo: "CRC", nombre: "Costa Rica — Colón", simbolo: "₡" },
  { codigo: "SVC", nombre: "El Salvador — Colón (histórico)", simbolo: "₡" },
  { codigo: "NIO", nombre: "Nicaragua — Córdoba", simbolo: "C$" },
  { codigo: "PAB", nombre: "Panamá — Balboa", simbolo: "B/." },
  { codigo: "BZD", nombre: "Belice — Dólar", simbolo: "BZ$" },
  { codigo: "MXN", nombre: "México — Peso Mexicano", simbolo: "$" },
  { codigo: "DOP", nombre: "República Dominicana — Peso Dominicano", simbolo: "RD$" },
  { codigo: "CUP", nombre: "Cuba — Peso Cubano", simbolo: "$" },
  { codigo: "COP", nombre: "Colombia — Peso Colombiano", simbolo: "$" },
  { codigo: "VES", nombre: "Venezuela — Bolívar Soberano", simbolo: "Bs." },
  { codigo: "PEN", nombre: "Perú — Sol", simbolo: "S/" },
  { codigo: "BOB", nombre: "Bolivia — Boliviano", simbolo: "Bs." },
  { codigo: "CLP", nombre: "Chile — Peso Chileno", simbolo: "$" },
  { codigo: "ARS", nombre: "Argentina — Peso Argentino", simbolo: "$" },
  { codigo: "PYG", nombre: "Paraguay — Guaraní", simbolo: "₲" },
  { codigo: "UYU", nombre: "Uruguay — Peso Uruguayo", simbolo: "$" },
  { codigo: "BRL", nombre: "Brasil — Real", simbolo: "R$" },
  { codigo: "GYD", nombre: "Guyana — Dólar", simbolo: "$" },
  { codigo: "SRD", nombre: "Surinam — Dólar", simbolo: "$" },
  { codigo: "CAD", nombre: "Canadá — Dólar Canadiense", simbolo: "C$" },
  { codigo: "EUR", nombre: "España / Europa — Euro", simbolo: "€" },
  { codigo: "GBP", nombre: "Reino Unido — Libra", simbolo: "£" },
];

export default function PlanesFarmaceuticoConfigPage() {
  const navigate = useNavigate();
  const { paisId } = usePaisFiltro();
  const {
    planesBase,
    planesConfig,
    paises,
    crearPlanBase,
    crearPlanConfig,
    eliminarPlanBase,
    actualizarPlanBase,
    loading,
  } = usePlanes({ pais_id: paisId || undefined });

  const planesFarmaceutico = planesBase.filter((p) => p.tipo === "farmaceutico");

  // ── Estados para CREAR plan base ──
  const [dialogoCrearPlanAbierto, setDialogoCrearPlanAbierto] = useState(false);
  const [nuevoPlan, setNuevoPlan] = useState({
    nombre: "",
    descripcion: "",
    precio_base: "",
    moneda: "USD",
    periodicidad: "mensual",
  });

  // ── Estados para EDITAR plan base ──
  const [dialogoEditarAbierto, setDialogoEditarAbierto] = useState(false);
  const [planAEditar, setPlanAEditar] = useState<PlanBase | null>(null);

  // ── Estados para ELIMINAR plan base ──
  const [dialogoEliminarAbierto, setDialogoEliminarAbierto] = useState(false);
  const [planAEliminar, setPlanAEliminar] = useState<string | null>(null);

  // ── Estados para SHEET (Drawer) de configuración por país ──
  const [sheetAbierto, setSheetAbierto] = useState(false);
  const [nuevaConfig, setNuevaConfig] = useState({
    plan_base_id: "",
    pais_id: "",
    moneda_local: "USD",
    precio_local: "",
    precio_anual: "",
  });

  // ── Handlers CREAR plan base ──
  const handleCrearPlan = async () => {
    await crearPlanBase({
      nombre: nuevoPlan.nombre,
      descripcion: nuevoPlan.descripcion,
      tipo: "farmaceutico",
      precio_base: parseFloat(nuevoPlan.precio_base),
      moneda: nuevoPlan.moneda,
      periodicidad: nuevoPlan.periodicidad,
    });
    setDialogoCrearPlanAbierto(false);
    setNuevoPlan({ nombre: "", descripcion: "", precio_base: "", moneda: "USD", periodicidad: "mensual" });
  };

  // ── Handlers EDITAR ──
  const abrirEditar = (plan: PlanBase) => {
    setPlanAEditar(plan);
    setDialogoEditarAbierto(true);
  };

  const handleActualizarPlanBase = async () => {
    if (!planAEditar) return;
    await actualizarPlanBase(planAEditar.id, {
      nombre: planAEditar.nombre,
      descripcion: planAEditar.descripcion,
      limite_medicos: planAEditar.limite_medicos,
      limite_pacientes: planAEditar.limite_pacientes,
    });
    setDialogoEditarAbierto(false);
    setPlanAEditar(null);
  };

  // ── Handlers ELIMINAR ──
  const confirmarEliminar = (id: string) => {
    setPlanAEliminar(id);
    setDialogoEliminarAbierto(true);
  };

  const handleEliminarPlanBase = async () => {
    if (!planAEliminar) return;
    await eliminarPlanBase(planAEliminar);
    setDialogoEliminarAbierto(false);
    setPlanAEliminar(null);
  };

  // ── Handlers CREAR configuración por país (en Sheet) ──
  const handleCrearConfig = async () => {
    await crearPlanConfig({
      plan_base_id: nuevaConfig.plan_base_id,
      pais_id: nuevaConfig.pais_id,
      moneda_local: nuevaConfig.moneda_local,
      precio_local: parseFloat(nuevaConfig.precio_local),
      precio_anual: nuevaConfig.precio_anual ? parseFloat(nuevaConfig.precio_anual) : undefined,
    });
    setSheetAbierto(false);
    setNuevaConfig({
      plan_base_id: "",
      pais_id: "",
      moneda_local: "USD",
      precio_local: "",
      precio_anual: "",
    });
  };

  if (loading) return <p className="p-6">Cargando planes...</p>;

  return (
    <div className="p-6 space-y-6">
      {/* ── Breadcrumb / Botón Volver ── */}
      <div className="flex items-center gap-2 mb-2">
        <Button
          variant="ghost"
          size="sm"
          onClick={() => navigate("/admin-ezpay")}
          className="text-[#1E5C8E] hover:text-[#1E5C8E]/80 hover:bg-[#1E5C8E]/10 -ml-2"
        >
          <ArrowLeft className="w-4 h-4 mr-1" />
          Volver al Panel Maestro
        </Button>
      </div>

      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Configuracion Planes Farmaceutico</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Gestiona planes para empresas farmaceuticas
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" size="sm">
            <svg className="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            Recargar
          </Button>
          <Button size="sm" onClick={() => setDialogoCrearPlanAbierto(true)}>
            <Plus className="w-4 h-4 mr-2" />
            Nuevo Plan
          </Button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="bg-white p-4 rounded-lg border">
          <p className="text-sm text-gray-500">Planes Base</p>
          <p className="text-2xl font-bold">{planesFarmaceutico.length}</p>
        </div>
        <div className="bg-white p-4 rounded-lg border">
          <p className="text-sm text-gray-500">Configuraciones</p>
          <p className="text-2xl font-bold">{planesConfig.length}</p>
        </div>
        <div className="bg-white p-4 rounded-lg border">
          <p className="text-sm text-gray-500">Paises</p>
          <p className="text-2xl font-bold">{paises.length}</p>
        </div>
        <div className="bg-white p-4 rounded-lg border">
          <p className="text-sm text-gray-500">Precio Base Max</p>
          <p className="text-2xl font-bold">
            {planesFarmaceutico.length > 0
              ? Math.max(...planesFarmaceutico.map((p) => p.precio_base || 0))
              : 0}{" "}
            USD
          </p>
        </div>
      </div>

      {/* ── TABLA PLANES BASE ── */}
      <div className="bg-white rounded-lg border overflow-hidden">
        <div className="p-4 border-b">
          <h2 className="text-lg font-semibold">Planes Base Farmaceutico</h2>
        </div>
        <div className="p-4">
          <div className="relative mb-4">
            <input
              type="text"
              placeholder="Buscar plan..."
              className="w-full pl-10 pr-4 py-2 border rounded-lg focus:ring-2 focus:ring-[#1E5C8E] focus:border-transparent"
            />
            <svg className="absolute left-3 top-2.5 w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nombre</TableHead>
                <TableHead>Descripcion</TableHead>
                <TableHead>Precio Base</TableHead>
                <TableHead>Moneda</TableHead>
                <TableHead>Periodicidad</TableHead>
                <TableHead>Estado</TableHead>
                <TableHead className="text-right">Acciones</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {planesFarmaceutico.map((plan) => (
                <TableRow key={plan.id}>
                  <TableCell className="font-medium">{plan.nombre}</TableCell>
                  <TableCell>{plan.descripcion}</TableCell>
                  <TableCell>{plan.precio_base}</TableCell>
                  <TableCell>
                    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                      {plan.moneda || "USD"}
                    </span>
                  </TableCell>
                  <TableCell>{plan.periodicidad || "Mensual"}</TableCell>
                  <TableCell>
                    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      Activo
                    </span>
                  </TableCell>
                  <TableCell className="text-right space-x-2">
                    <Button variant="ghost" size="icon" onClick={() => abrirEditar(plan)}>
                      <Edit className="w-4 h-4" />
                    </Button>
                    <Button variant="ghost" size="icon" onClick={() => confirmarEliminar(plan.id)}>
                      <Trash2 className="w-4 h-4 text-red-500" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>

      {/* ── TABLA CONFIGURACIONES POR PAÍS ── */}
      <div className="bg-white rounded-lg border overflow-hidden">
        <div className="p-4 border-b flex justify-between items-center">
          <h2 className="text-lg font-semibold">Configuraciones por Pais</h2>
          {/* ── SHEET (Drawer) para crear configuración ── */}
          <Sheet open={sheetAbierto} onOpenChange={setSheetAbierto}>
            <SheetTrigger asChild>
              <Button size="sm">
                <Plus className="w-4 h-4 mr-2" />
                Nueva Configuracion
              </Button>
            </SheetTrigger>
            <SheetContent side="right" className="w-[500px] sm:w-[600px] overflow-y-auto">
              <SheetHeader>
                <SheetTitle>Nueva Configuracion por Pais</SheetTitle>
                <SheetDescription>
                  Define precios y moneda para un plan base en un pais especifico.
                </SheetDescription>
              </SheetHeader>
              <div className="grid gap-4 py-6">
                <div>
                  <Label>Plan Base</Label>
                  <Select
                    value={nuevaConfig.plan_base_id}
                    onValueChange={(value) =>
                      setNuevaConfig({ ...nuevaConfig, plan_base_id: value })
                    }
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Seleccionar plan" />
                    </SelectTrigger>
                    <SelectContent>
                      {planesFarmaceutico.map((p) => (
                        <SelectItem key={p.id} value={p.id}>
                          {p.nombre}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Pais</Label>
                  <Select
                    value={nuevaConfig.pais_id}
                    onValueChange={(value) =>
                      setNuevaConfig({ ...nuevaConfig, pais_id: value })
                    }
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Seleccionar pais" />
                    </SelectTrigger>
                    <SelectContent>
                      {paises.map((p) => (
                        <SelectItem key={p.id} value={p.id}>
                          {p.nombre} ({p.codigo})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>Precio Local Mensual</Label>
                  <Input
                    type="number"
                    value={nuevaConfig.precio_local}
                    onChange={(e) =>
                      setNuevaConfig({ ...nuevaConfig, precio_local: e.target.value })
                    }
                    placeholder="0"
                  />
                </div>
                <div>
                  <Label>Precio Anual</Label>
                  <Input
                    type="number"
                    value={nuevaConfig.precio_anual}
                    onChange={(e) =>
                      setNuevaConfig({ ...nuevaConfig, precio_anual: e.target.value })
                    }
                    placeholder="0"
                  />
                </div>
                <div>
                  <Label>Moneda Local</Label>
                  <Select
                    value={nuevaConfig.moneda_local}
                    onValueChange={(value) =>
                      setNuevaConfig({ ...nuevaConfig, moneda_local: value })
                    }
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Seleccionar moneda" />
                    </SelectTrigger>
                    <SelectContent className="max-h-[300px]">
                      {MONEDAS_LATAM.map((m) => (
                        <SelectItem key={m.codigo} value={m.codigo}>
                          {m.simbolo} — {m.nombre}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <SheetFooter className="flex-col gap-2 sm:flex-row">
                <SheetClose asChild>
                  <Button variant="outline">Cancelar</Button>
                </SheetClose>
                <Button onClick={handleCrearConfig}>Crear Configuracion</Button>
              </SheetFooter>
            </SheetContent>
          </Sheet>
        </div>
        <div className="p-4">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Plan</TableHead>
                <TableHead>Pais</TableHead>
                <TableHead>Precio Local</TableHead>
                <TableHead>Precio Anual</TableHead>
                <TableHead>Comision</TableHead>
                <TableHead>Descuento</TableHead>
                <TableHead>Estado</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {planesConfig.map((cfg) => (
                <TableRow key={cfg.id}>
                  <TableCell>{cfg.plan_base?.nombre || cfg.plan_id}</TableCell>
                  <TableCell>
                    <span className="inline-flex items-center gap-1">
                      <span className="text-xs font-medium bg-gray-100 px-1.5 py-0.5 rounded">
                        {cfg.pais?.codigo || cfg.pais_id}
                      </span>
                      {cfg.pais?.nombre || cfg.pais_id}
                    </span>
                  </TableCell>
                  <TableCell>{cfg.precio_local}</TableCell>
                  <TableCell>{cfg.precio_anual || "—"}</TableCell>
                  <TableCell>{cfg.comision_aplicada || 0}%</TableCell>
                  <TableCell>{cfg.descuento_porcentaje || 0}%</TableCell>
                  <TableCell>
                    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      Activo
                    </span>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>

      {/* ── Dialog: Crear Plan Base ── */}
      <Dialog open={dialogoCrearPlanAbierto} onOpenChange={setDialogoCrearPlanAbierto}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>Crear Nuevo Plan</DialogTitle>
            <DialogDescription>Define los detalles del nuevo plan farmaceutico.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div>
              <Label>Nombre</Label>
              <Input
                value={nuevoPlan.nombre}
                onChange={(e) => setNuevoPlan({ ...nuevoPlan, nombre: e.target.value })}
                placeholder="Ej: Farmaceutico Basico"
              />
            </div>
            <div>
              <Label>Descripcion</Label>
              <Input
                value={nuevoPlan.descripcion}
                onChange={(e) => setNuevoPlan({ ...nuevoPlan, descripcion: e.target.value })}
                placeholder="Descripcion del plan"
              />
            </div>
            <div>
              <Label>Precio Base</Label>
              <Input
                type="number"
                value={nuevoPlan.precio_base}
                onChange={(e) => setNuevoPlan({ ...nuevoPlan, precio_base: e.target.value })}
                placeholder="0"
              />
            </div>
            <div>
              <Label>Moneda</Label>
              <Select
                value={nuevoPlan.moneda}
                onValueChange={(value) => setNuevoPlan({ ...nuevoPlan, moneda: value })}
              >
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {MONEDAS_LATAM.slice(0, 5).map((m) => (
                    <SelectItem key={m.codigo} value={m.codigo}>
                      {m.simbolo} — {m.nombre}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Periodicidad</Label>
              <Select
                value={nuevoPlan.periodicidad}
                onValueChange={(value) => setNuevoPlan({ ...nuevoPlan, periodicidad: value })}
              >
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="mensual">Mensual</SelectItem>
                  <SelectItem value="anual">Anual</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogoCrearPlanAbierto(false)}>
              Cancelar
            </Button>
            <Button onClick={handleCrearPlan}>Crear Plan</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Dialog: Editar Plan Base ── */}
      <Dialog open={dialogoEditarAbierto} onOpenChange={setDialogoEditarAbierto}>
        <DialogContent className="sm:max-w-[500px]">
          <DialogHeader>
            <DialogTitle>Editar Plan</DialogTitle>
            <DialogDescription>Modifica los detalles del plan.</DialogDescription>
          </DialogHeader>
          {planAEditar && (
            <div className="grid gap-4 py-4">
              <div>
                <Label>Nombre</Label>
                <Input
                  value={planAEditar.nombre}
                  onChange={(e) => setPlanAEditar({ ...planAEditar, nombre: e.target.value })}
                />
              </div>
              <div>
                <Label>Descripcion</Label>
                <Input
                  value={planAEditar.descripcion || ""}
                  onChange={(e) => setPlanAEditar({ ...planAEditar, descripcion: e.target.value })}
                />
              </div>
              <div>
                <Label>Limite Medicos</Label>
                <Input
                  type="number"
                  value={planAEditar.limite_medicos ?? ""}
                  onChange={(e) =>
                    setPlanAEditar({
                      ...planAEditar,
                      limite_medicos: e.target.value ? parseInt(e.target.value) : undefined,
                    })
                  }
                  placeholder="Dejar vacio para ilimitado"
                />
              </div>
              <div>
                <Label>Limite Pacientes</Label>
                <Input
                  type="number"
                  value={planAEditar.limite_pacientes ?? ""}
                  onChange={(e) =>
                    setPlanAEditar({
                      ...planAEditar,
                      limite_pacientes: e.target.value ? parseInt(e.target.value) : undefined,
                    })
                  }
                  placeholder="Dejar vacio para ilimitado"
                />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogoEditarAbierto(false)}>
              Cancelar
            </Button>
            <Button onClick={handleActualizarPlanBase}>Guardar Cambios</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Dialog: Confirmar Eliminación ── */}
      <Dialog open={dialogoEliminarAbierto} onOpenChange={setDialogoEliminarAbierto}>
        <DialogContent className="sm:max-w-[400px]">
          <DialogHeader>
            <DialogTitle>Confirmar Eliminacion</DialogTitle>
            <DialogDescription>
              Esta accion no se puede deshacer. El plan base sera eliminado permanentemente.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogoEliminarAbierto(false)}>
              Cancelar
            </Button>
            <Button variant="destructive" onClick={handleEliminarPlanBase}>
              Eliminar
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
