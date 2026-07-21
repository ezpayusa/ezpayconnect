# 📋 PROMPT PARA SIGUIENTE SESIÓN — EzPayConnect

> Última actualización: 2026-07-21 (frente planes-visitador cerrado en prod + diseño del enrolamiento visitador→médico para el piloto)

**Reglas de siempre:** Claude = revisor/prompts · CC = ejecuta · Codex = recon solo-lectura · Oscar aprueba cada paso · prompts en bloque copiable · un bloque por vez · no guardar memoria hasta que lo pida.

## ▶️ ANTES DE NADA
1. Leé en la RAÍZ de `C:\dev\ezpayconnect`: este archivo, `ESTADO_PROYECTO_EZPAYCONNECT.md`, `DISENO-PLANES-LAB-FARMACIA.md` y `DISENO-ENROLAMIENTO-VISITADOR-MEDICO.md`.
2. **Chequeo diario O1** (a CC): `supabase db query --linked "select count(*) as nacidas_sin_correlativo from recetas where id > 2725 and numero_correlativo is null;"` (debe dar 0).

**DEUDAS QUE MUERDEN:** `schema_migrations` en 047 → NUNCA `db push`, aplicar con `-f`. NUNCA `functions deploy` sin nombre. Build = `vite build`. Deploy = git push a `main` → Vercel. `supabase/fixes/*.sql` se commitean con `git add -f`. **tsc baseline = 82** (NO subirlo). Edge functions con CORS cerrado a med.ezpayconnect.com (no se prueban en preview).

## ✅ CERRADO HOY EN PROD (20-21 jul) — frente planes-visitador
- **65d0d80** cableado el checkout real de la landing `PlanesVisitadorPage` (cae el último `alert()` de checkout falso, cierra hallazgo [D]).
- **c56ca65** UI para editar `duracion_dias`/`visitas_incluidas` del plan visitador (`PlanesVisitadorConfigPage` + `atributos` en `CrearPlanBaseDTO`). Causa raíz del `atributos={}`.
- **4d56c9d** columnas Vigencia/Visitas en la tabla de planes visitador.
- **Diagnóstico:** la "vigencia de 1 año" y la "notificación faltante" NO eran bugs. Vigencia real = 30 días (default por `atributos={}`); notificación = solo polling de 60s (se creó bien). Único gap = dato: "Plan Plus" con `atributos={}`.
- **limite_medicos: CONFIRMADO INERTE** para visitador (la mig 116 borró el `trg_limite_visitas` de la 061). Campo muerto en el config, candidato a limpiar.

**PENDIENTE DE DATOS (no código):** rellenar `atributos` de los planes visitador viejos en `{}` (Plan Oro, Plata, Plus) desde la UI (Editar→días/visitas→Guardar) o seed `-f`. El contrato de prueba `2db5f85a` (bolsa NULL) no se corrige solo.

## 🎯 FRENTE NUEVO — ENROLAMIENTO VISITADOR→MÉDICO (PARA EL PILOTO, arrancar acá)
Ver diseño completo en `DISENO-ENROLAMIENTO-VISITADOR-MEDICO.md`. Resumen:
Objetivo: visitador invita/registra un médico en su clínica → el médico nace enrolado bajo el **LAB** (`medicos.lab_enrolador_id`, nivel empresa) → head-start de agenda (5 días exclusivos, 18 meses / 8 visitas). Consentimiento del médico = gratis (completa su registro desde el email).
**80% ya construido y VIVO en prod** (migs 193-201): `lab_enrolador_id`, RPC `enrolar_medico`, capacidad booleana `'enrolamiento'`, `prioridad_activa`, y el gate `trg_gate_head_start_lab` (mig 196) que YA enforcea el head-start. Falta el "combustible" (nada setea `lab_enrolador_id` desde UI) + el form del visitador.
Plan (backend primero): **B1 DB** (-f, aditivo): `empresa_enroladora_id` en `invitaciones_medico` + `registrar_medico_desde_invitacion` setea `lab_enrolador_id` cuando la invitación traiga empresa (backward-compatible). **B2 Edge**: rama visitador con capacidad `'enrolamiento'` en `crear-invitacion-medico` (deploy CON NOMBRE). **B3 Frontend**: form del visitador (superficie a decidir) + handler de `PV002` en agendar.
Decisiones de Oscar: (1) superficie del form (PWA visitador `/visitador/*` es la natural, ¿o portal/ambas?); (2) admin EzPay activa la capacidad `'enrolamiento'` por empresa (pantalla `CapacidadesTiersPais`); (3) defaults del head-start (5d/8v/18m) o ajustar.

## 📋 OTROS PENDIENTES DEL PILOTO
0. **INFRA (Oscar, dashboard):** Supabase FREE→Pro + compute Small/Medium + verificar cap de Realtime. Único bloqueante de infra, 2-3 días antes del piloto.
1. **Limpieza datos QA** (~38 filas, -f, reversible). Dejar `admin.qa@`, `doctor@prueba.com`, `laboratorio.qa@`, `farmacia.qa@` + empresas backfilleadas.
2. **Chicos/medios:** rellenar atributos de planes viejos, limpiar `limite_medicos` inerte del config visitador, foto en Personal de clínica, `procesar-recordatorios` lock, `enviar-push-campana` LIMIT, Realtime chat filtro server-side, `WebAppDashboard` count, los 2 `console.log` de debug en `PlanesVisitadorConfigPage`.
3. **Diferidos post-piloto.**

Arrancamos con: B1 del enrolamiento (o lo que decida Oscar).
