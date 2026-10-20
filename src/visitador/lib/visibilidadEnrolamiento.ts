// Visibilidad del enrolamiento (pieza 6): cosmética, la barrera son las RPCs (PV016 tipo de empresa, PV014 módulo).
// Módulo aparte y mínimo porque lo importa VisitadorLayout, que va en el chunk de entrada.

/** Enrolar y solicitar alta: laboratorio farmacéutico con el módulo 'enrolamiento' vigente. */
export function puedeEnrolarEmpresa(tipoEmpresa: string | null | undefined, tieneEnrolamiento: boolean): boolean {
  return tipoEmpresa === 'laboratorio_farmaceutico' && tieneEnrolamiento
}
