Evaluación de EZPayConnect para un piloto de salud pública

Fecha de revisión: 14 de septiembre de 2026. Autor: Codex (recon de solo lectura). Método: solo lectura. No se modificaron archivos, no se ejecutaron migraciones, no se corrieron pruebas que escriban en la base y no se utilizó Git. Estado: exploratorio. No aprobado. No en desarrollo activo.

Dictamen ejecutivo

EZPayConnect tiene una base aprovechable para atención ambulatoria, pero actualmente no está listo para operar el piloto gubernamental descrito —hospitales y centros rurales de un área de salud— sin cambios sustanciales.

La distancia principal no está en React o Supabase. Está en cinco capacidades:

Organización sanitaria territorial: no se encontró una red nacional con áreas, distritos y establecimientos.
Continuidad asistencial: no se encontró referencia/contrarreferencia ni identidad longitudinal de población resuelta entre establecimientos.
Operación rural: existe caché, pero no un expediente clínico que permita registrar atención sin conexión y sincronizarla.
Programas y vigilancia: faltan módulos estructurados para vacunación, prenatal, crecimiento infantil y vigilancia epidemiológica.
Garantías operativas y de seguridad: hay controles importantes, pero también deuda explícita y falta de evidencia actual sobre recuperación, capacidad y auditoría completa.

Sí puede servir como base de una evaluación ambulatoria acotada. No hay evidencia para presentarlo hoy como sistema hospitalario integral ni como expediente nacional. Tampoco sería responsable asignarle un porcentaje de preparación o una fecha de entrega con este reconocimiento.

Alcance y confiabilidad de la evidencia

Se revisó código de src/, Edge Functions, migraciones —hasta 292_higiene_planes_base_nombres_y_anon.sql—, archivos de supabase/fixes/, auditorías y memoria local.

Tres niveles de evidencia:

Comprobado localmente: definición o comportamiento presente en código/SQL.
Documentado históricamente: una auditoría o memoria afirma que se probó o desplegó.
No verificado: estado efectivo de producción, configuración de servicios, volumen, rendimiento y cumplimiento.

No se consultó la base viva ni los paneles de Supabase/Vercel más allá de lo indicado. No se ejecutó el harness.

Documentos solicitados
Documento	Resultado
EZPAYCONNECT_ARCHITECTURE.md	No localizado con ese nombre en las ubicaciones revisadas.
NUCLEO_REUTILIZABLE_SAAS.md	No localizado con ese nombre.
PLAN_SEGURIDAD_DIA_2.md	Encontrado en el Escritorio. Describe el sistema anterior de PHP/JSON y .htaccess; no acredita el estado del SaaS médico actual.
Memoria del proyecto	Accesible: CLAUDE.md y memoria local del repo.
1. Modelo de datos y tenancy

El aislamiento está distribuido entre varias relaciones; no hay un único árbol organizativo sanitario.

Dimensión	Evidencia	Función actual
País	configuracion_pais, pais_id	Segmentación territorial/comercial.
Clínica	clinicas, medico_clinicas, personal_clinica	Pertenencia de médicos y personal.
Paciente	pacientes.medico_id, clinica_primaria_id, auth_user_id	Médico, clínica primaria y acceso al portal.
Proveedor	empresas_proveedoras, cuentas_proveedor.empresa_id	Entidad comercial y sus usuarios.
Farmacia/sucursal	farmacias.empresa_id	Sucursales vinculadas a una empresa.

Encaje con la organización pública:

Nivel requerido	Encaje actual
Red nacional	País sirve como agrupador, pero no representa una autoridad sanitaria.
Área de salud/departamento	No encontrado.
Distrito de salud	No encontrado.
Establecimiento	clinicas es la aproximación más cercana.
Hospital nacional/regional, CAP, CS, puesto	No hay tipología institucional con niveles de atención.
Servicios dentro del hospital	No hay organización por unidades, camas y episodios de hospitalización.

Referencia y contrarreferencia: no existe un circuito formal. referidos_paciente es invitación de amigos, no referencia clínica. El chat médico-paciente no constituye coordinación formal entre establecimientos. Brecha alta y bloqueante.

2. Identidad, roles y aislamiento

Roles existentes: sistema/clínica (super_admin, admin_clinica, gerente, medico, soporte, vendedor, cliente), personal clínico (asistente_medico, enfermeria, secretaria), territorial (admin_pais), comercial B2B (asesor_comercial, supervisor_comercial), farmacia y laboratorio (con sus propios catálogos).

Faltan roles para: epidemiología, estadística sanitaria, vigilancia, auditoría ministerial, dirección de área/distrito. admin_pais no cubre esos niveles intermedios.

Fortalezas de aislamiento verificadas: RLS y autorización en backend, helpers privados SECURITY DEFINER con search_path='', pertenencia clínica, confinamiento por empresa/sucursal, protección de columnas de identidad (mig 262), gate de país fail-closed (mig 265-271).

Límite: private.asesores_a_cargo() gobierna visibilidad comercial, no es control general del expediente. admin_pais es un rol de negocio EZPay con alcance por país sobre pacientes/citas/recetas, no una matriz ministerial de acceso por finalidad y responsabilidad.

3. Historial clínico y expediente

Existe: notas SOAP (expediente_notas), antecedentes narrativos, signos vitales con captura/validación y autoría, prescripción con reglas de negocio (rol médico, catálogo, dosis, acuse), despacho con token y expiración, laboratorio con solicitud/resultado/liberación al paciente, documentos y consentimiento versionado.

Recetas no son completamente libres: emitir_receta() exige rol médico, paciente existente, medicamento del catálogo activo, dosis y frecuencia, y acuse para categorías que lo requieren.

Fase 4 de laboratorio: implementada, no solo diseñada (liberado_al_paciente, liberar_examen_al_paciente(), paciente_examenes()). Resultados siguen como texto/archivo, sin normalización por analito/unidades/rangos.

Brechas: vacunación, embarazo/prenatal, crecimiento infantil (curvas/percentiles), enfermedades crónicas (registro longitudinal), hospitalización (camas, ingresos/traslados/egresos), identidad poblacional (índice maestro, fusión de duplicados), integridad documental (versionado de notas).

Interoperabilidad: no se encontró HL7, FHIR, CIE-10/CIE-11, SNOMED CT, LOINC, ni códigos farmacológicos estándar. Diagnósticos en texto, medicamentos en catálogo propio, laboratorio en catálogo propio + texto/archivos.

4. Escala, rendimiento y conectividad rural

Arquitectura: React 19/TS/Vite + Supabase + Vercel. Demuestra backend lógico centralizado; no permite deducir réplicas, backups o recursos configurados.

Avances: índices para rutas frecuentes, algunos .limit(), división de bundles, Sentry con scrubbing.

Límites: consultas combinadas en el navegador (useHistorialCompleto.ts), inventario sin paginación explícita en algún flujo, sin pruebas de carga nacional, sin evidencia operativa actual de recuperación probada o disponibilidad.

Offline: existe algo, pero no lo necesario. El service worker (src/sw.ts) hace precaché de la app y caché NetworkFirst de lecturas a Supabase (100 entradas, 24h). No hay registro durable de escrituras clínicas pendientes, sincronización, resolución de conflictos ni reconciliación de pacientes creados sin conexión. Cargar la app o leer una respuesta cacheada no permite atender confiablemente sin conexión.

Notificaciones: push transaccional funcional para avisos, pero documenta que marca el envío antes de intentarlo y no reintenta si falla. No hay sistema de alertas epidemiológicas con destinatarios territoriales y escalamiento.

5. Seguridad, privacidad y cumplimiento

Los hallazgos de auditorías históricas (julio 2026) tienen correcciones posteriores documentadas en migraciones concretas (234, 235, 236-239, 262, 265-271). Esto confirma cambios locales, no permisos efectivos del servidor en este momento.

Deuda explícita reconocida: el harness (tests/rls/harness_run.py) acepta once excepciones conocidas como DEUDA (bandeja/buzón/QR de confinamiento, helper estructural de push, entre otras). "Harness aceptado" no significa "cero hallazgos".

Auditoría de datos clínicos: hay piezas útiles (auditoria_logs, identidad del actor desde JWT, reveal_log para recetas) pero no trazabilidad completa de toda lectura/exportación/modificación, ni historial inmutable de cada versión de nota.

No verificado: cifrado de infraestructura, región/residencia de datos, retención, MFA, backups y restauración, accesos operativos del proveedor, contratos y subencargados.

Cumplimiento: la Ley de Acceso a la Información Pública guatemalteca contempla protección de datos personales; no se hizo validación jurídica integral. No se encontró integración con SIGSA (sistema de información gerencial de salud de Guatemala).

6. Inventario y farmacia a escala pública

Existe: inventario por farmacia/sucursal, stock/lote/vencimiento, importación de catálogo, permisos de inventario, dispensación, comisiones comerciales.

Falta: jerarquía bodega central→regional→establecimiento, transferencias entre bodegas, kardex completo de movimientos, cuarentena/retiros de lote, cadena de frío, pronóstico de desabastecimiento territorial.

Matching medicamento↔inventario: evidencia de evolución hacia identificador (farmacia_medicamentos.medicamento_id), pero no está acreditada su incorporación completa en el SQL revisado; el descuento de stock en despacho sigue por nombre en al menos una función.

Distancia respecto a logística gubernamental: alta. Comisiones, precios y delivery comercial no sustituyen abastecimiento institucional.

7. Brechas priorizadas para un piloto real
A. Ya existe y conserva utilidad funcional

Agenda/citas ambulatorias, registro de pacientes sin cuenta digital, notas SOAP, signos vitales, catálogo y prescripción, resultados de laboratorio con liberación, portal del paciente, notificaciones internas básicas.

B. Existe, pero necesita adaptación (P0/P1)

Alcance institucional y permisos (P0), seguridad clínica y confinamiento — deuda reconocida (P0), identidad del paciente (P0), expediente y autoría (P0), dispensación e inventario si incluye farmacia (P0), catálogos y diagnósticos (P1), laboratorio (P1), modelo comercial no representa provisión pública (P1).

C. No existe y es indispensable para el piloto

Trabajo clínico offline (P0), referencia/contrarreferencia (P0), organización sanitaria territorial (P0), auditoría clínica integral (P0), recuperación y continuidad no acreditada (P0), gobierno de datos y autorización institucional no acreditado (P0), reporte sanitario del piloto (P1 obligatorio), vacunación/prenatal/infancia/crónicos si el piloto cubre esos servicios (P1).

D. Puede diferirse, con exclusión explícita del alcance

Sistema hospitalario integral completo, integración con equipos de laboratorio/imagen, interoperabilidad HL7/FHIR completa, logística nacional avanzada, analítica poblacional/detección de brotes, capacidad nacional completa, IA clínica y funciones comerciales de promoción.

Conclusión final

EZPayConnect ofrece una base ambulatoria reutilizable con avances reales de seguridad. Su modelo actual sigue organizado alrededor de clínica, médico, paciente y proveedores privados.

Para el piloto propuesto, offline clínico, organización territorial, identidad compartida, referencias, trazabilidad y reporte sanitario son brechas centrales. Si además se espera sustituir operación hospitalaria o administrar abastecimiento público, el alcance faltante crece considerablemente.

Veredicto: apto como base para evaluar y delimitar un piloto; no acreditado como listo para operar ese piloto con datos reales, y muy lejos de demostrar preparación nacional.
