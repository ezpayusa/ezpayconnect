import { useState } from "react";
import { usePlanes } from "@/hooks/usePlanes";
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
  DialogTrigger,
} from "@/components/ui/dialog";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Trash2, Edit, Plus } from "lucide-react";
import type { PlanBase } from "@/types/planes";

export default function PlanesClinicaConfigPage() {
  const {
    planesBase,
    planesConfig,
    crearPlanConfig,
    eliminarPlanBase,
    actualizarPlanBase,
    loading,
  } = usePlanes();

  // ── Estados para CREAR configuración por país (existente, intacto) ──
  const [dialogoCrearAbierto, setDialogoCrearAbierto] = useState(false);
  const [nuevaConfig, setNuevaConfig] = useState({
    plan_base_id: "",
    pais: "",
    precio_mensual: "",
    precio_anual: "",
    moneda: "USD",
  });

  // ── Estados para EDITAR plan base (nuevo) ──
  const [dialogoEditarAbierto, setDialogoEditarAbierto] = useState(false);
  const [planAEditar, setPlanAEditar] = useState<PlanBase | null>(null);

  // ── Estados para ELIMINAR plan base (nuevo) ──
  const [dialogoEliminarAbierto, setDialogoEliminarAbierto] = useState(false);
  const [planAEliminar, setPlanAEliminar] = useState<string | null>(null);

  // ── Handlers CREAR (existentes, intactos) ──
  const handleCrearConfig = async () => {
    await crearPlanConfig({
      plan_base_id: nuevaConfig.plan_base_id,
      pais: nuevaConfig.pais,
      precio_mensual: parseFloat(nuevaConfig.precio_mensual),
      precio_anual: parseFloat(nuevaConfig.precio_anual),
      moneda: nuevaConfig.moneda,
    });
    setDialogoCrearAbierto(false);
    setNuevaConfig({
      plan_base_id: "",
      pais: "",
      precio_mensual: "",
      precio_anual: "",
      moneda: "USD",
    });
  };

  // ── Handlers EDITAR (nuevo) ──
  const abrirEditar = (plan: PlanBase) => {
    setPlanAEditar(plan);
    setDialogoEditarAbierto(true);
  };

  const handleActualizarPlanBase = async () => {
    if (!planAEditar) return;
    await actualizarPlanBase(planAEditar.id, {
      nombre: planAEditar.nombre,
      descripcion: planAEditar.descripcion,
      max_medicos: planAEditar.max_medicos,
      max_pacientes: planAEditar.max_pacientes,
      max_citas_mes: planAEditar.max_citas_mes,
    });
    setDialogoEditarAbierto(false);
    setPlanAEditar(null);
  };

  // ── Handlers ELIMINAR (fix + nuevo) ──
  const confirmarEliminar = (id: string) => {
    setPlanAEliminar(id);
    setDialogoEliminarAbierto(true);
  };

  const handleEliminarPlanBase = async () => {
    if (!planAEliminar) return;
    await eliminarPlanBase(planAEliminar); // ✅ FIX: usa eliminarPlanBase, no eliminarPlanConfig
    setDialogoEliminarAbierto(false);
    setPlanAEliminar(null);
  };

  if (loading) return <p className="p-6">Cargando planes...</p>;

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Configuración de Planes Clínica</h1>

        {/* ── Botón + (crear config por país) — EXISTENTE, INTACTO ── */}
        <Dialog open={dialogoCrearAbierto} onOpenChange={setDialogoCrearAbierto}>
          <DialogTrigger asChild>
            <Button>
              <Plus className="w-4 h-4 mr-2" />
              Nueva Configuración por País
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Crear Configuración de País</DialogTitle>
              <DialogDescription>
                Define precios y moneda para un plan base en un país específico.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div>
                <Label>Plan Base</Label>
                <select
                  className="w-full border rounded p-2"
                  value={nuevaConfig.plan_base_id}
                  onChange={(e) =>
                    setNuevaConfig({ ...nuevaConfig, plan_base_id: e.target.value })
                  }
                >
                  <option value="">Selecciona un plan base</option>
                  {planesBase.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.nombre}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <Label>País</Label>
                <Input
                  value={nuevaConfig.pais}
                  onChange={(e) =>
                    setNuevaConfig({ ...nuevaConfig, pais: e.target.value })
                  }
                  placeholder="ej: Guatemala"
                />
              </div>
              <div>
                <Label>Precio Mensual</Label>
                <Input
                  type="number"
                  value={nuevaConfig.precio_mensual}
                  onChange={(e) =>
                    setNuevaConfig({ ...nuevaConfig, precio_mensual: e.target.value })
                  }
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
                />
              </div>
              <div>
                <Label>Moneda</Label>
                <Input
                  value={nuevaConfig.moneda}
                  onChange={(e) =>
                    setNuevaConfig({ ...nuevaConfig, moneda: e.target.value })
                  }
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDialogoCrearAbierto(false)}>
                Cancelar
              </Button>
              <Button onClick={handleCrearConfig}>Guardar</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

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
              <TableHead>Citas/mes</TableHead>
              <TableHead className="text-right">Acciones</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {planesBase.map((plan) => (
              <TableRow key={plan.id}>
                <TableCell className="font-medium">{plan.nombre}</TableCell>
                <TableCell>{plan.descripcion}</TableCell>
                <TableCell>{plan.max_medicos}</TableCell>
                <TableCell>{plan.max_pacientes}</TableCell>
                <TableCell>{plan.max_citas_mes}</TableCell>
                <TableCell className="text-right space-x-2">
                  {/* ── Botón EDITAR (fix: ahora funciona) ── */}
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => abrirEditar(plan)}
                  >
                    <Edit className="w-4 h-4" />
                  </Button>

                  {/* ── Botón ELIMINAR (fix: confirma + usa eliminarPlanBase) ── */}
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

      {/* ── TABLA CONFIGURACIONES POR PAÍS (existente, intacta) ── */}
      <section>
        <h2 className="text-lg font-semibold mb-2">Configuraciones por País</h2>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Plan Base</TableHead>
              <TableHead>País</TableHead>
              <TableHead>Precio Mensual</TableHead>
              <TableHead>Precio Anual</TableHead>
              <TableHead>Moneda</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {planesConfig.map((cfg) => (
              <TableRow key={cfg.id}>
                <TableCell>{cfg.plan_base?.nombre || cfg.plan_base_id}</TableCell>
                <TableCell>{cfg.pais}</TableCell>
                <TableCell>{cfg.precio_mensual}</TableCell>
                <TableCell>{cfg.precio_anual}</TableCell>
                <TableCell>{cfg.moneda}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </section>

      {/* ════════════════════════════════════════════
          DIALOGOS NUEVOS / FIX
          ════════════════════════════════════════════ */}

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
      <Dialog open={dialogoEditarAbierto} onOpenChange={setDialogoEditarAbierto}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Editar Plan Base</DialogTitle>
            <DialogDescription>Modifica los límites y datos del plan.</DialogDescription>
          </DialogHeader>
          {planAEditar && (
            <div className="grid gap-4 py-4">
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
                <Label>Máx. Médicos</Label>
                <Input
                  type="number"
                  value={planAEditar.max_medicos ?? 0}
                  onChange={(e) =>
                    setPlanAEditar({
                      ...planAEditar,
                      max_medicos: parseInt(e.target.value) || 0,
                    })
                  }
                />
              </div>
              <div>
                <Label>Máx. Pacientes</Label>
                <Input
                  type="number"
                  value={planAEditar.max_pacientes ?? 0}
                  onChange={(e) =>
                    setPlanAEditar({
                      ...planAEditar,
                      max_pacientes: parseInt(e.target.value) || 0,
                    })
                  }
                />
              </div>
              <div>
                <Label>Máx. Citas/mes</Label>
                <Input
                  type="number"
                  value={planAEditar.max_citas_mes ?? 0}
                  onChange={(e) =>
                    setPlanAEditar({
                      ...planAEditar,
                      max_citas_mes: parseInt(e.target.value) || 0,
                    })
                  }
                />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogoEditarAbierto(false)}>
              Cancelar
            </Button>
            <Button onClick={handleActualizarPlanBase}>Guardar cambios</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
