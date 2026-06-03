-- ============================================
-- Migración 008: Habilitar Realtime para chat_mensajes
-- ============================================

-- Habilitar replicación para que Supabase Realtime funcione
ALTER TABLE chat_mensajes REPLICA IDENTITY FULL;

-- Asegurar que la tabla esté en la publicación de supabase_realtime
-- (Esto depende de la configuración de Supabase, pero el comando REPLICA IDENTITY es el más importante)
