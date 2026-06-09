-- Verificar si pacientes tiene auth_user_id y si el paciente 22 lo tiene
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'pacientes' 
ORDER BY ordinal_position;
