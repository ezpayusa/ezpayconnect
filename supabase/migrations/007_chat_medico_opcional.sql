-- ============================================
-- Migración 007: Hacer medico_id opcional en chat_mensajes
-- ============================================

ALTER TABLE chat_mensajes ALTER COLUMN medico_id DROP NOT NULL;
