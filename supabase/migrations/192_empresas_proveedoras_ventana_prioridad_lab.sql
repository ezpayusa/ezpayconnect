-- 192 Canal laboratorios — capa lab_enrolador_id (paso 1, mínima y aislada)
-- Agrega config de "ventana de prioridad de agenda" POR LAB ENROLADOR en empresas_proveedoras
-- (la entidad empresa/lab; tipo='laboratorio_clinico'). Ambas NULL a propósito: el default global
-- (5 días / 8 visitas) vive en la lógica de la app/RPC, NO se hardcodea en la columna.
-- NO agrega otras columnas, triggers ni RPCs. NO toca medicos ni tablas de agenda/disponibilidad.

ALTER TABLE public.empresas_proveedoras
  ADD COLUMN IF NOT EXISTS dias_ventaja_reserva      int,
  ADD COLUMN IF NOT EXISTS ventana_prioridad_visitas int;

COMMENT ON COLUMN public.empresas_proveedoras.dias_ventaja_reserva IS
  'Días de exclusividad del lab enrolador antes de que otros labs puedan reservar un slot recién abierto del médico enrolado. NULL = default global (5) en la RPC.';
COMMENT ON COLUMN public.empresas_proveedoras.ventana_prioridad_visitas IS
  'Cantidad de visitas completadas antes de que expire la ventana de prioridad del lab sobre ese médico. NULL = default global (8) en la RPC.';
