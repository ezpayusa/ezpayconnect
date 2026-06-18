import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import FarmaciaReportesPage from "./FarmaciaReportesPage"

// Render test del panel poblado SIN DB ni browser: se inyectan respuestas MOCK
// de los dos RPC. recetas incluye una celda colapsada por k-anon ('(otros)') tal
// como la devolvería el servidor (la supresión <5 ocurre server-side; el cliente
// solo recibe el bucket). Valores <1000 para evitar ambigüedad de separadores Intl.
//
// NOTA: este test cierra el riesgo de CÓDIGO del render poblado. La confirmación
// con DATA REAL de dispensaciones queda ATADA al prereq de datos reales: hoy
// dispensaciones=0 en toda la base → ambos RPC devuelven [] para cualquier usuario;
// sembrar dispensaciones QA ampliaría el footprint de cleanup y se descarta.

const FINANZAS = [
  { sucursal_id: 1, sucursal: "Farmacia Centro", dispensaciones: 42, total_dispensado: 850, items: 120 },
  { sucursal_id: 2, sucursal: "Farmacia Norte", dispensaciones: 7, total_dispensado: 300, items: 20 },
]
const RECETAS = [
  { sucursal_id: 1, sucursal: "Farmacia Centro", medicamento: "Paracetamol 500mg", veces_dispensado: 8, cantidad_total: 96 },
  { sucursal_id: 1, sucursal: "Farmacia Centro", medicamento: "(otros)", veces_dispensado: 3, cantidad_total: 9 }, // k-anon (<5)
]

const rpc = vi.fn((name: string) => {
  if (name === "stats_finanzas_sucursal") return Promise.resolve({ data: FINANZAS, error: null })
  if (name === "stats_recetas_sucursal") return Promise.resolve({ data: RECETAS, error: null })
  return Promise.resolve({ data: null, error: new Error("rpc no mockeado: " + name) })
})

vi.mock("@/lib/supabase", () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...(a as [string])) } }))
vi.mock("@/farmacia/hooks/useFarmaciaPermisos", () => ({
  useFarmaciaPermisos: () => ({ tienePermiso: () => true, loading: false }),
}))

describe("FarmaciaReportesPage — render poblado (mock RPC)", () => {
  beforeEach(() => rpc.mockClear())

  it("renderiza ambas secciones pobladas, mapea filas y muestra la nota k-anon", async () => {
    render(<FarmaciaReportesPage />)

    // Títulos de las dos secciones
    expect(await screen.findByText("Dispensaciones y montos")).toBeInTheDocument()
    expect(screen.getByText("Medicamentos dispensados")).toBeInTheDocument()

    // Finanzas: filas mapeadas (sucursal aparece en finanzas + recetas → getAllByText)
    await waitFor(() => expect(screen.getAllByText("Farmacia Centro").length).toBeGreaterThan(0))
    expect(screen.getByText("Farmacia Norte")).toBeInTheDocument()
    expect(screen.getByText("42")).toBeInTheDocument()   // dispensaciones
    expect(screen.getByText("850")).toBeInTheDocument()  // total_dispensado
    expect(screen.getByText("120")).toBeInTheDocument()  // items

    // Recetas: medicamento nombrado + bucket k-anon visible
    expect(screen.getByText("Paracetamol 500mg")).toBeInTheDocument()
    expect(screen.getByText("(otros)")).toBeInTheDocument()

    // Nota de privacidad k-anon
    expect(screen.getByText(/se agrupan como «\(otros\)»/)).toBeInTheDocument()

    // Ambos RPC consultados
    expect(rpc).toHaveBeenCalledWith("stats_finanzas_sucursal", expect.anything())
    expect(rpc).toHaveBeenCalledWith("stats_recetas_sucursal", expect.anything())
  })
})
