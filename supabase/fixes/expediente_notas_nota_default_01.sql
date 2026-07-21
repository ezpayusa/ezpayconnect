-- Versiona el DEFAULT '' de expediente_notas.nota que prod ya tiene y que las migraciones no reflejan.
-- Migracion 001 creo `nota TEXT NOT NULL` SIN default; prod tiene DEFAULT ''::text, por eso el guardado
-- SOAP funciona sin enviar 'nota'. En una DB reconstruida desde migraciones, el INSERT sin 'nota' fallaria.
-- Idempotente: SET DEFAULT al mismo valor es no-op en prod. No se toca el NOT NULL (se mantiene igual que prod).
ALTER TABLE public.expediente_notas ALTER COLUMN nota SET DEFAULT ''::text;
