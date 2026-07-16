-- Fix: archivo_url guardado como URL pública (getPublicUrl viejo) -> normalizar a solo el PATH.
-- El bucket resultados-examenes es privado; los lectores hacen openSignedUrl('resultados-examenes', path).
-- Con URL completa, la firma falla. Solo toca filas con el patrón viejo.
UPDATE public.examenes
SET archivo_url = split_part(archivo_url, '/object/public/resultados-examenes/', 2)
WHERE archivo_url LIKE '%/object/public/resultados-examenes/%';
