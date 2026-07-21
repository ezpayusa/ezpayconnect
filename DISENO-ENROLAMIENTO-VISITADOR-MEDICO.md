# 🩺 DISEÑO — Enrolamiento visitador → médico (prioridad de agenda por lab)

> Fecha: 2026-07-21 · Estado: **diseñado, para el piloto.** 80% del backend ya vivo en prod (migs 193-201); faltan 3 piezas.
> Seguridad: `schema_migrations` en 047 → aplicar con `-f`; edge deploy CON NOMBRE.

## Objetivo
Un visitador, en la clínica del médico, lo invita al software. El médico nace **enrolado bajo el laboratorio (empresa)** del visitador vía `medicos.lab_enrolador_id`. Eso le da al lab **head-start de agenda**: ventana exclusiva para reservar visitas con "su" médico. El médico **confirma completando su propio registro** desde el email de invitación (consentimiento gratis, ya existe en el pipeline).

## Granularidad (decisión tomada por Oscar)
El vínculo es a nivel **LAB/empresa**, NO por visitador individual — `lab_enrolador_id` → `empresas_proveedoras`. Cualquier visitador del lab hereda la prioridad. (La visita sí tiene atribución individual: `visitas_agendadas.cuenta_proveedor_id` / `propuesta_por`.)

## Lo que YA está construido y VIVO en prod (migs 193-201)
- `medicos.lab_enrolador_id` (→ empresas_proveedoras) + `lab_enrolador_fecha`; trigger de inmutabilidad **BEFORE UPDATE** (mig 193) → NO bloquea setearlo en el INSERT del alta.
- RPC `enrolar_medico(p_medico_id)` (mig 197): un visitador reclama un médico YA existente. Gate `empresa_tiene_capacidad(empresa,'enrolamiento')` (mig 201). **Sin frontend (0 refs).**
- Capacidad booleana `'enrolamiento'` en `empresa_capacidades` (migs 198-200). Admin EzPay la activa por empresa (pantalla `CapacidadesTiersPais`).
- `prioridad_activa(p_medico_id)` (mig 195): activa = `(visitas_completadas < ventana_prioridad_visitas[def 8]) AND (now < lab_enrolador_fecha + 18 meses)`.
- **Gate VIVO `trg_gate_head_start_lab`** (mig 196, BEFORE INSERT en `visitas_agendadas`): si el médico tiene lab prioritario, ese lab reserva cualquier fecha; otro lab NO puede reservar dentro de `CURRENT_DATE + dias_ventaja` (def 5) → `RAISE 'PV002'`.
- Confirmado: la mig 116 borró `trg_limite_visitas` (el viejo cupo de la 061). `limite_medicos` quedó **inerte**.

## Lo que FALTA (3 piezas + 1 UX) — recon CC del 21-jul
**B1 — DB (`-f`, aditivo, riesgo cero):**
- Columna `empresa_enroladora_id uuid REFERENCES empresas_proveedoras(id)` en `invitaciones_medico` (hoy 14 cols, sin empresa).
- Reemplazar `registrar_medico_desde_invitacion` para setear `lab_enrolador_id = v_invitacion.empresa_enroladora_id` (+ `lab_enrolador_fecha = now()`) en el `INSERT INTO medicos`, SOLO si la invitación trae empresa. NULL = comportamiento actual (admin/clínica intactos). El trigger de inmutabilidad es BEFORE UPDATE → el INSERT lo permite.

**B2 — Edge `crear-invitacion-medico`:** el gate actual (:37-60) solo autoriza super_admin/admin_clinica/gerente. Agregar rama: solicitante es `cuenta_proveedor` activa (`mi_empresa_proveedor()`) + `empresa_tiene_capacidad(empresa,'enrolamiento')` → graba `empresa_enroladora_id`. Deploy **CON NOMBRE**. CORS cerrado (no se prueba en preview).

**B3 — Frontend:** form del visitador para invitar médico (mismos campos que admin), gateado por capacidad `'enrolamiento'`. Superficie a decidir (PWA visitador `/visitador/*` = natural para campo). `registrar-medico-invitacion` NO necesita cambios (el lab sale de la invitación, leída dentro de la RPC).

**UX (+):** handler del error `PV002` en el flujo de agendar (hoy 0 captura en src/) → mensaje amigable "fecha reservada para el lab con prioridad" en vez del error crudo.

## Orden y regla
B1 (DB) → B2 (edge) → B3 (frontend). Cada bloque: recon-confirmado → CC ejecuta → build/verify (tsc ≤82, vite build) → Oscar aprueba → merge. No hace falta tocar `prioridad_activa` ni `trg_gate_head_start_lab` (ya funcionan).
