# Pendientes EZPayConnect — derivados del recon FHIR (24-sep-2026)

Origen: recon de solo lectura de Codex sobre qué tan lejos está EZPayConnect de poder exponerse como FHIR R4. No se implementa FHIR ahora; estos cuatro pendientes valen por sí mismos (integridad clínica, seguridad regulatoria y seguridad del paciente).
Estado: pendientes aprobados por Oscar el 24-sep-2026. Flujo normal: Claude arma prompts → Codex recon / CC implementa → dry-run → verificación independiente → commit → push solo con autorización.

**Estado al 25-sep-2026:** P1, P2 y P3 **CERRADOS** (aplicados en prod, verificados en sesión independiente y mergeados a main). P4 **sigue abierto**. Detalle en `docs/CIERRE-2026-09-25.md`.

## P1 — URGENTE: verificar la ruta alternativa de emisión de recetas

> **CERRADO 25-sep-2026** — mig 328: la emisión de recetas pasa solo por `emitir_receta` (REVOKE del INSERT directo en `recetas` y `receta_items`; el front usa siempre la RPC). Merge `f142d46`.

- Hallazgo: `src/hooks/useRecetas.ts` conserva una ruta directa de emisión de recetas alternativa a la RPC `emitir_receta` (contrato vigente en mig 316), controlada por una bandera.
- Riesgo: si la bandera está activa en producción, pueden emitirse recetas sin las validaciones del núcleo regulatorio O1 (rol médico, catálogo activo, dosis/frecuencia, acuse, pertenencia de 316/320).
- Primer paso: verificar de forma independiente el valor efectivo de la bandera en producción (build de Vercel / variable de entorno / fuente real que lea el hook). No asumir por el código.
- Si está activa: tratar como incidente de seguridad regulatoria — apagarla, medir cuántas recetas salieron por la ruta directa y desde cuándo.
- Si está inactiva: planificar la eliminación de la ruta muerta para que no pueda reactivarse.

## P2 — Unidades de signos vitales (glucosa)

> **CERRADO 25-sep-2026** — mig 330: rangos de plausibilidad en `capturar_signo_vital` (SV001/SV002) + 8 CHECK `sv_*_rango`; unidades canónicas (glucosa mg/dL entero, temperatura °C) visibles en captura y en todas las superficies; merge `23801a8`. Mig 331: toma vacía rechazada (SV003) y el form detecta números inválidos; merge `34e4490`.

- Hallazgo: `signos_vitales` no persiste unidades; el formulario (`src/clinica/components/FormularioVitales.tsx`) muestra unidades para la mayoría de campos pero la glucosa aparece solo como "Glucosa", sin unidad. `presion_arterial` es TEXT.
- Riesgo: seguridad del paciente — 95 mg/dL y 95 mmol/L son valores clínicamente muy distintos.
- Alcance mínimo: documentar unidad canónica, significado y precisión de cada vital; fijar y mostrar explícitamente la unidad de glucosa. Superficies: `src/lib/unidades.ts`, `FormularioVitales.tsx`, `src/hooks/useSignosVitalesCita.ts`, contrato de migs 160/254.

## P3 — Persistir el ID del examen de catálogo

> **CERRADO 25-sep-2026** — mig 332: `examenes.catalogo_id` con FK RESTRICT + backfill, órdenes solo por `crear_orden_examen_medico` / `crear_orden_examen_walkin`, `tipo` congelado como snapshot; front con ítems `{catalogo_id}`/`{nombre}` y marca "fuera de catálogo"; merge `4477dd6`. Mig 333: sin INSERT directo de órdenes; merge `6a0ebfa`. Spec: `docs/specs/P3-ordenes-examen-spec-2026-09-25.md`.

- Hallazgo: al ordenar exámenes (`src/pages/ConsultaPage.tsx`, `src/laboratorio/hooks/useLaboratorio.ts`) se guarda solo el nombre del examen; no queda FK al concepto de `examenes_catalogo` (mig 063).
- Riesgo: renombrar un examen del catálogo rompe la identidad de las órdenes históricas.
- Alcance: nueva migración que agregue la referencia al catálogo conservando el nombre capturado; actualizar los dos consumidores.

## P4 — Revisiones inmutables de notas clínicas y resultados

> **ABIERTO** al 25-sep-2026.

- Hallazgo: `src/hooks/useConsultas.ts` actualiza la misma fila de `expediente_notas` (SOAP y diagnóstico incluidos) sin conservar la versión anterior. `subirResultado` en laboratorio también sobrescribe resultado/archivo/estado.
- Riesgo: integridad del expediente — una corrección borra lo que había antes, sin autor ni motivo del cambio.
- Alcance: tabla(s) de revisiones con autor, fecha, motivo y vínculo a la revisión anterior; una nota o resultado confirmado se corrige con una revisión nueva, no con UPDATE. Diseñar primero con Codex (recon) antes de pasar a CC.

## Diferidos (no son pendientes activos)

Resto del top-10 del recon — identificadores externos opacos, tabla de equivalencias terminológicas (CIE-10/LOINC/ATC), metadatos homogéneos de archivos, posología estructurada, resultados de laboratorio por analito, separación de campos clínicos vs comerciales para exportación. Se activan cuando aparezca el primer cliente que pida integración HL7/FHIR.
