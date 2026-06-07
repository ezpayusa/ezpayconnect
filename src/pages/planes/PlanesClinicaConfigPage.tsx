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
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
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
import Draggable from "react-draggable";

// Monedas latinoamericanas + España/USA/Canadá (match con planes-utils.ts)
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

export default function PlanesClinicaConfigPage() {
  const navigate = useNavigate();
  const { paisId } = usePaisFiltro();
  const {
    planesBase,
    planesConfig,
    paises,
    crearPlanConfig,
    eliminarPlanBase,
    actualizarPlanBase,
    loading,
  } = usePlanes({ pais_id: paisId || undefined });

  // ── Estados para CREAR configuración por país ──
  const [dialogoCrearAbierto, setDialogoCrearAbierto] = useState(false);
  const [nuevaConfig, setNuevaConfig] = useState({
    plan_base_id: "",
    pais_id: "",
    moneda_local: "USD",
    precio_local: "",
    precio_anual: "",
  });

  // ── Estados para EDITAR plan base ──
  const [dialogoEditarAbierto, setDialogoEditarAbierto] = useState(false);
  const [planAEditar, setPlanAEditar] = useState<PlanBase | null>(null);

  // ── Estados para ELIMINAR plan base ──
  const [dialogoEliminarAbierto, setDialogoEliminarAbierto] = useState(false);
  const [planAEliminar, setPlanAEliminar] = useState<string | null>(null);

  // ── Handlers CREAR ──
  const handleCrearConfig = async () => {
    await crearPlanConfig({
      plan_base_id: nuevaConfig.plan_base_id,
      pais_id: nuevaConfig.pais_id,
      moneda_local: nuevaConfig.moneda_local,
      precio_local: parseFloat(nuevaConfig.precio_local),
      precio_anual: nuevaConfig.precio_anual ? parseFloat(nuevaConfig.precio_anual) : undefined,
    });
    setDialogoCrearAbierto(false);
    setNuevaConfig({
      plan_base_id: "",
      pais_id: "",
      moneda_local: "USD",
      precio_local: "",
      precio_anual: "",
    });
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
          <h1 className="text-2xl font-bold">Configuración de Planes Clínica</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Gestiona los planes base y sus configuraciones por país
          </p>
        </div>

        {/* ── Botón + (abre diálogo draggable) ── */}
        <Button onClick={() => setDialogoCrearAbierto(true)}>
          <Plus className="w-4 h-4 mr-2" />
          Nueva Configuración por País
        </Button>
      </div>

      {/* ── DIÁLOGO DRAGGABLE (sin Dialog de Radix) ── */}
      {dialogoCrearAbierto && (
        <>
          {/* Overlay oscuro */}
          <div 
            className="fixed inset-0 bg-black/50 z-50"
            onClick={() => setDialogoCrearAbierto(false)}
          />

          {/* Ventana draggable */}
          <Draggable handle=".drag-handle" bounds="body">
            <div className="fixed top-20 left-1/2 -translate-x-1/2 z-[60] w-[500px] bg-white rounded-lg border shadow-lg">
              {/* Header arrastrable */}
              <div className="drag-handle flex items-center justify-between p-4 border-b cursor-move bg-gray-50 rounded-t-lg select-none">
                <div>
                  <h2 className="text-lg font-semibold">Crear Configuración de País</h2>
                  <p className="text-sm text-muted-foreground">
                    Define precios y moneda para un plan base en un país específico.
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8"
                  onClick={() => setDialogoCrearAbierto(false)}
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>

              {/* Contenido */}
              <div className="p-4 space-y-4">
                <div>
                  <Label>Plan Base</Label>
                  <Select
                    value={nuevaConfig.plan_base_id}
                    onValueChange={(value) =>
                      setNuevaConfig({ ...nuevaConfig, plan_base_id: value })
                    }
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Selecciona un plan base" />
                    </SelectTrigger>
                    <SelectContent>
                      {planesBase.map((p) => (
                        <SelectItem key={p.id} value={p.id}>
                          {p.nombre}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label>País</Label>
                  <Select
                    value={nuevaConfig.pais_id}
                    onValueChange={(value) =>
                      setNuevaConfig({ ...nuevaConfig, pais_id: value })
                    }
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Selecciona un país" />
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
                  <Label>Precio Local</Label>
                  <Input
                    type="number"
                    value={nuevaConfig.precio_local}
                    onChange={(e) =>
                      setNuevaConfig({ ...nuevaConfig, precio_local: e.target.value })
                    }
                    placeholder="Precio mensual en moneda local"
                  />
                </div>
                <div>
                  <Label>Precio Anual (opcional)</Label>
                  <Input
                    type="number"
                    value={nuevaConfig.precio_anual}
                    onChange={(e) =>
                      setNuevaConfig({ ...nuevaConfig, precio_anual: e.target.value })
                    }
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
                      <SelectValue placeholder="Selecciona una moneda" />
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

              {/* Footer */}
              <div className="flex justify-end gap-2 p-4 border-t">
                <Button variant="outline" onClick={() => setDialogoCrearAbierto(false)}>
                  Cancelar
                </Button>
                <Button onClick={handleCrearConfig}>Guardar</Button>
              </div>
            </div>
          </Draggable>
        </>
      )}

      {/* ── TABLA PLANES BASE ── */}
      <section>
        <h2 className="text-lg font-semibold mb-2">Planes Base Clínica</h2>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Nombre</TableHead>
              <TableHead>Descripción</TableHead>
              <TableHead>Médicos</TableHead>
              <TableHead>Pacientes</TableHead>
              <TableHead className="text-right">Acciones</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {planesBase.map((plan) => (
              <TableRow key={plan.id}>
                <TableCell className="font-medium">{plan.nombre}</TableCell>
                <TableCell>{plan.descripcion}</TableCell>
                <TableCell>{plan.limite_medicos ?? "Ilimitado"}</TableCell>
                <TableCell>{plan.limite_pacientes ?? "Ilimitado"}</TableCell>
                <TableCell className="text-right space-x-2">
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => abrirEditar(plan)}
                  >
                    <Edit className="w-4 h-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => confirmarEliminar(plan.id)}
                  >
                    <Trash2 className="w-4 h-4 text-red-500" />
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </section>

      {/* ── TABLA CONFIGURACIONES POR PAÍS ── */}
      <section>
        <h2 className="text-lg font-semibold mb-2">Configuraciones por País</h2>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Plan Base</TableHead>
              <TableHead>País</TableHead>
              <TableHead>Precio Local</TableHead>
              <TableHead>Precio Anual</TableHead>
              <TableHead>Moneda</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {planesConfig.map((cfg) => (
              <TableRow key={cfg.id}>
                <TableCell>{cfg.plan_base?.nombre || cfg.plan_id}</TableCell>
                <TableCell>{cfg.pais?.nombre || cfg.pais_id}</TableCell>
                <TableCell>{cfg.precio_local}</TableCell>
                <TableCell>{cfg.precio_anual ?? "—"}</TableCell>
                <TableCell>{cfg.moneda_local}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </section>

      {/* ── AlertDialog: Confirmar Eliminación ── */}
      <AlertDialog open={dialogoEliminarAbierto} onOpenChange={setDialogoEliminarAbierto}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>¿Eliminar plan base?</AlertDialogTitle>
            <AlertDialogDescription>
              Esta acción no se puede deshacer. Si hay clínicas usando este plan, podría causar inconsistencias.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setPlanAEliminar(null)}>
              Cancelar
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={handleEliminarPlanBase}
              className="bg-red-600 hover:bg-red-700"
            >
              Eliminar
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* ── Dialog: Editar Plan Base ── */}
      {dialogoEditarAbierto && (
        <>
          <div 
            className="fixed inset-0 bg-black/50 z-50"
            onClick={() => setDialogoEditarAbierto(false)}
          />
          <Draggable handle=".drag-handle" bounds="body">
            <div className="fixed top-20 left-1/2 -translate-x-1/2 z-[60] w-[500px] bg-white rounded-lg border shadow-lg">
              <div className="drag-handle flex items-center justify-between p-4 border-b cursor-move bg-gray-50 rounded-t-lg select-none">
                <div>
                  <h2 className="text-lg font-semibold">Editar Plan Base</h2>
                  <p className="text-sm text-muted-foreground">Modifica los límites y datos del plan.</p>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8"
                  onClick={() => setDialogoEditarAbierto(false)}
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
              {planAEditar && (
                <div className="p-4 space-y-4">
                  <div>
                    <Label>Nombre</Label>
                    <Input
                      value={planAEditar.nombre}
                      onChange={(e) =>
                        setPlanAEditar({ ...planAEditar, nombre: e.target.value })
                      }
                    />
                  </div>
                  <div>
                    <Label>Descripción</Label>
                    <Input
                      value={planAEditar.descripcion || ""}
                      onChange={(e) =>
                        setPlanAEditar({ ...planAEditar, descripcion: e.target.value })
                      }
                    />
                  </div>
                  <div>
                    <Label>Límite Médicos</Label>
                    <Input
                      type="number"
                      value={planAEditar.limite_medicos ?? ""}
                      onChange={(e) =>
                        setPlanAEditar({
                          ...planAEditar,
                          limite_medicos: e.target.value ? parseInt(e.target.value) : undefined,
                        })
                      }
                      placeholder="Dejar vacío para ilimitado"
                    />
                  </div>
                  <div>
                    <Label>Límite Pacientes</Label>
                    <Input
                      type="number"
                      value={planAEditar.limite_pacientes ?? ""}
                      onChange={(e) =>
                        setPlanAEditar({
                          ...planAEditar,
                          limite_pacientes: e.target.value ? parseInt(e.target.value) : undefined,
                        })
                      }
                      placeholder="Dejar vacío para ilimitado"
                    />
                  </div>
                  <div className="flex justify-end gap-2 pt-2">
                    <Button variant="outline" onClick={() => setDialogoEditarAbierto(false)}>
                      Cancelar
                    </Button>
                    <Button onClick={handleActualizarPlanBase}>Guardar cambios</Button>
                  </div>
                </div>
              )}
            </div>
          </Draggable>
        </>
      )}
    </div>
  );
}
