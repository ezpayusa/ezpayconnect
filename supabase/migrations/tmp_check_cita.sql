SELECT id, paciente_id, medico_id, estado, motivo, fecha, hora_inicio 
FROM citas 
WHERE estado = 'agendada' 
ORDER BY created_at DESC 
LIMIT 5;
