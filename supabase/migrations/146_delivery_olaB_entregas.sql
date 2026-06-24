-- ============================================================
-- 146 · DELIVERY Fase 1 — OLA B: tabla entregas + 4 permisos + RLS (INERTE: nace vacía e inescribible)
-- ------------------------------------------------------------
-- Alcance EXACTO: tabla entregas (PK, FKs, UNIQUE, 6 CHECKs, índices); 4 permisos finos (entregas_cobrar → TECHO
-- 117; entregas_ver/_actualizar_estado/_gestionar operativos); RLS espejo PURO de 141/143 + slice delivery;
-- REVOKE I/U/D/TRUNCATE/TRIGGER/REFERENCES de anon+authenticated + GRANT SELECT a authenticated.
-- NO RPCs (Ola C). NO front. La tabla nace VACÍA e inescribible salvo owner/DEFINER → 0 callers → INERTE.
-- Idempotente.
-- ============================================================

-- 1) Tabla entregas ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.entregas (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receta_base_id    bigint  NOT NULL REFERENCES public.recetas(id),            -- recetas(id) referenciable (recetas_id_uniq)
  farmacia_id       integer NOT NULL REFERENCES public.farmacias(id),          -- la SUCURSAL
  empresa_id        uuid    NOT NULL REFERENCES public.empresas_proveedoras(id),  -- denormalizado p/ RLS (= farmacias.empresa_id)
  paciente_id       bigint  NOT NULL REFERENCES public.pacientes(id),          -- bigint (de recetas, no text de recetas_avanzadas)
  delivery_id       uuid    REFERENCES public.cuentas_proveedor(id),           -- repartidor; NULL hasta asignar
  estado            text    NOT NULL DEFAULT 'pendiente'
                      CHECK (estado IN ('pendiente','asignada','en_camino','entregada','fallida')),
  motivo_fallo      text    CHECK (motivo_fallo IN ('rechazada','ausente','direccion_mala')),
  direccion_entrega text,                                                      -- snapshot de pacientes.direccion (Ola C)
  telefono_contacto text,                                                      -- snapshot de pacientes.telefono (Ola C)
  lat               double precision,
  lng               double precision,                                          -- nullable; entrega válida sin coords
  monto             numeric(12,2),                                             -- snapshot SUM(dispensaciones.total_dispensado)
  metodo_cobro      text    CHECK (metodo_cobro IN ('efectivo','tarjeta','transferencia','sin_cobro')),
  cobrado           boolean NOT NULL DEFAULT false,
  cobrado_at        timestamptz,
  cobrado_por       uuid    REFERENCES public.cuentas_proveedor(id),
  evidencia_path    text,                                                      -- PATH en bucket privado (Ola D), no URL
  asignado_por      uuid,
  asignado_at       timestamptz,
  entregado_at      timestamptz,
  notas             text,
  intentos          integer NOT NULL DEFAULT 0,                               -- reaperturas (reasignar_entrega, Ola C)
  reabierta_at      timestamptz,
  reabierta_por     uuid    REFERENCES public.cuentas_proveedor(id),
  created_by        uuid,                                                      -- NULL = auto-al-despachar
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_entrega_receta_sucursal UNIQUE (receta_base_id, farmacia_id),
  CONSTRAINT chk_motivo_si_fallida CHECK ((estado='fallida') = (motivo_fallo IS NOT NULL)),
  CONSTRAINT chk_cobro_coherente   CHECK (cobrado=false OR (cobrado_at IS NOT NULL AND cobrado_por IS NOT NULL AND metodo_cobro IS NOT NULL)),
  CONSTRAINT chk_monto_no_negativo CHECK (monto IS NULL OR monto >= 0)
);

-- 2) Índices ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_entregas_delivery_estado ON public.entregas (delivery_id, estado);
CREATE INDEX IF NOT EXISTS idx_entregas_farmacia_estado ON public.entregas (farmacia_id, estado);
CREATE INDEX IF NOT EXISTS idx_entregas_empresa_estado  ON public.entregas (empresa_id, estado);

-- 3) Permisos (catálogo) + techo de entregas_cobrar -------------------------
INSERT INTO public.permisos_empresa_rol (tipo_empresa, rol, accion)
SELECT 'farmacia', v.rol, v.accion
FROM (VALUES
  ('delivery','entregas_ver'),('supervisor','entregas_ver'),('gerente_farmacia','entregas_ver'),
    ('admin','entregas_ver'),('finanzas','entregas_ver'),('pagador','entregas_ver'),
  ('supervisor','entregas_gestionar'),('gerente_farmacia','entregas_gestionar'),('admin','entregas_gestionar'),
  ('delivery','entregas_actualizar_estado'),('supervisor','entregas_actualizar_estado'),
    ('gerente_farmacia','entregas_actualizar_estado'),('admin','entregas_actualizar_estado'),
  ('delivery','entregas_cobrar'),('cajero','entregas_cobrar'),('gerente_farmacia','entregas_cobrar'),
    ('admin','entregas_cobrar'),('finanzas','entregas_cobrar'),('pagador','entregas_cobrar')
) AS v(rol, accion)
WHERE NOT EXISTS (
  SELECT 1 FROM public.permisos_empresa_rol p
  WHERE p.tipo_empresa='farmacia' AND p.rol=v.rol AND p.accion=v.accion
);
-- techo (Q2): entregas_cobrar no-delegable por override per-empresa (solo el admin lo reparte)
INSERT INTO public.acciones_techo (accion) VALUES ('entregas_cobrar') ON CONFLICT (accion) DO NOTHING;

-- 4) RLS: espejo PURO 141/143 + slice delivery -----------------------------
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS entregas_select ON public.entregas;
CREATE POLICY entregas_select ON public.entregas FOR SELECT TO authenticated
  USING (
    ( COALESCE(public.mi_empresa_proveedor() = empresa_id, false)
      AND COALESCE(private.sucursal_visible(farmacia_id), false)
      AND ( public.mi_rol_proveedor() <> 'delivery' OR delivery_id = auth.uid() ) )   -- delivery: solo SUS entregas
    OR COALESCE(private.tiene_rol(ARRAY['super_admin']), false)
  );

-- 5) Escritura DENEGADA (sin policy de write) + REVOKE de lo NO RLS-gated ----
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.entregas FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.entregas FROM anon;
GRANT  SELECT ON public.entregas TO authenticated;   -- lectura RLS-gated; escritura solo owner/DEFINER (Ola C)
