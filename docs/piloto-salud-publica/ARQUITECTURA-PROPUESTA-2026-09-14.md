Arquitectura propuesta para un piloto de salud pública de EZPayConnect

Autor: Codex (recon + diseño, solo lectura). Fecha: 14 de septiembre de 2026. Estado: propuesta para revisión de Oscar y equipo. NO aprobado. NO en desarrollo activo. Alcance: un área de salud, pocos hospitales y varios establecimientos rurales. Modalidad: solo lectura y diseño. No se crearon archivos, se escribió implementación ni se utilizó Git.

1. Decisión principal

Un dominio sanitario público separado del comercial, conservando React/TypeScript y Supabase/Postgres, con una aplicación y un proyecto Supabase independientes para el piloto real.

Dentro de ese proyecto, una sola base transaccional y un backend modular son suficientes como punto de partida. No se proponen microservicios, una base por establecimiento ni infraestructura nacional desde el inicio.

La separación tiene un costo (adaptar componentes clínicos existentes, mantener contratos de datos propios). A cambio evita que: admin_pais/super_admin comerciales hereden autoridad sobre pacientes públicos; una modificación territorial cambie el alcance de asesores/proveedores; publicidad/planes/capacidades comerciales condicionen la atención; dispositivos rurales compartan caché y sesiones con la app comercial.

Un esquema PostgreSQL separado dentro del mismo proyecto es técnicamente posible pero NO recomendado para datos reales: separa nombres y permisos, no separa credenciales privilegiadas, administración, recuperación ni capacidad de cómputo.

Convenciones: comprobado localmente / propuesta nueva / riesgo-trade-off. Las decisiones SP-01–SP-12 son todas nuevas, no sustituyen las D1-D12 comerciales.

2. Evidencia que condiciona el diseño
Ref	Comprobado localmente	Consecuencia arquitectónica
E1	private.clinicas_de() (mig 159) resuelve pertenencia clínica	No representa jerarquía territorial sanitaria
E2	private.asesores_a_cargo() (mig 264), jerarquía comercial de 2 niveles	No debe reutilizarse para establecimientos ni pacientes
E3	private.puede_admin_pais() fail-closed ante NULL (mig 265), guard de perfiles (mig 262)	Conservar el principio, no heredar autoridad comercial
E4	expediente_notas y signos vitales con captura/validación	Contenido reutilizable; falta versionado uniforme
E5	src/sw.ts cachea lecturas, no implementa comandos offline	Sincronización requiere pieza nueva
E6	consentimientos acumulativo, reveal_log para accesos concretos	Precedentes útiles, no auditoría integral
E7	push transaccional marca envío antes de intentarlo, sin reintento	Referencias/alertas necesitan entrega durable independiente
E8	matching medicamento↔inventario no acreditado completo	No asumir catálogo farmacológico reconciliado
3. Límites del piloto y decisiones fundamentales

Alcance: identificación/registro de personas, consulta ambulatoria y signos vitales, notas/diagnóstico/prescripción/resultados, referencia y contrarreferencia, captura offline en establecimientos seleccionados, auditoría y reporte sanitario, programas según cartera. Hospitales participan inicialmente vía consulta externa y recepción de referencias — hospitalización queda fuera salvo ampliación expresa.

Decisiones SP-01 a SP-12 (para revisión)
SP-01: proyecto Supabase, aplicación, origen web y credenciales del piloto separados del comercial.
SP-02: red_sanitaria es la frontera institucional de datos; país es contexto, no autorización suficiente.
SP-03: usuarios con múltiples asignaciones territoriales explícitas; ningún rol comercial concede acceso sanitario.
SP-04: autoridad administrativa territorial y acceso clínico a una persona son permisos distintos.
SP-05: identificador interno único por persona dentro de la red; documentos oficiales son identificadores asociados, no claves primarias obligatorias.
SP-06: encuentros/observaciones/versiones clínicas conservan autoría y procedencia; una nota firmada no se sobrescribe.
SP-07: offline mediante almacenamiento local y cola de operaciones; no se replica indiscriminadamente la base.
SP-08: sincronización idempotente; ningún conflicto clínico se resuelve automáticamente por "último guardado".
SP-09: una referencia es un proceso clínico independiente de citas y chat.
SP-10: toda entrega de información clínica online pasa por una interfaz auditable; RLS es defensa adicional, no la única.
SP-11: catálogos versionados y reportes sanitarios específicos desde el piloto; FHIR completo puede esperar.
SP-12: la activación depende de pruebas de aislamiento, desconexión, recuperación y operación clínica, no solo de terminar pantallas.
4. Arquitectura general y convivencia con EZPayConnect

Componentes: aplicación sanitaria React (origen independiente) ↔ almacén local protegido (datos mínimos + cola de operaciones pendientes) ↔ API sanitaria (identidad, autorización, auditoría) ↔ Postgres del piloto (territorio, personas, clínica) + archivos clínicos privados → procesamiento durable (notificaciones/reportes/sincronización) → repositorio independiente de respaldo. El SaaS comercial se conecta solo mediante intercambio autorizado y acotado, sin acceso implícito al piloto.

Módulos del backend: organización e identidad institucional; personas y reconciliación; encuentros y documentación clínica; referencias; sincronización; programas sanitarios; auditoría y reportes. Operaciones que necesiten atomicidad terminan en una transacción PostgreSQL — varias llamadas independientes desde una Edge Function NO cuentan como transacción.

Separación interna de datos (esquemas propuestos): territorio, identidad, clinico, integracion, auditoria. Las tablas clínicas no se exponen directamente al navegador — verificar, no asumir, qué esquemas expone la API de Supabase.

Relación con datos existentes: correspondencia por código de país (no FK entre proyectos) con configuracion_pais; mapeo opcional de clinicas a establecimientos solo con incorporación autorizada; correspondencia opcional de pacientes con personas vía reconciliación (no copiar toda la población comercial); importación selectiva de expediente_notas como documento histórico con procedencia; medicamentos como insumo para equivalencias, no autoridad automática; cuentas_proveedor/planes/asesores sin pertenencia ni autoridad implícita en el dominio sanitario. Entidad nueva: correspondencias_origen (sistema de origen, tipo de objeto, id externo, objeto destino, método, responsable, fecha).

Trade-off aceptado: no hay joins directos ni identidad de sesión compartida inicialmente — un mismo médico puede tener dos accesos separados. Preferible a que su rol privado se vuelva autoridad pública por coincidencia de correo.

5. Organización sanitaria y autorización territorial
Entidades nuevas

redes_sanitarias, unidades_territoriales (área/distrito, jerárquico), establecimientos, adscripciones_establecimiento (dependencia administrativa), coberturas_establecimiento (territorios atendidos — distinto de la adscripción), servicios_establecimiento, rutas_asistenciales.

Decisión importante: adscripción administrativa ≠ cobertura asistencial. Un hospital puede depender del nivel nacional y atender varios distritos — no forzar todo hospital a colgar de un distrito ficticio.

Invariantes: toda unidad/establecimiento pertenece a una red; sin ciclos ni relaciones entre redes distintas; tipos padre/hijo explícitos; un establecimiento tiene una adscripción vigente y puede tener varias coberturas; cambiar adscripción no reescribe historia; código oficial no sustituye el identificador interno; establecimiento inactivo no recibe asignaciones ordinarias; una ruta asistencial ofrece destinos, no concede acceso a expedientes.

Identidad institucional separada

actores_sanitarios, roles_sanitarios (catálogo independiente: médico, enfermería, admisión, coordinación de referencias, epidemiología, estadística, farmacia, auditoría, administración territorial), asignaciones_sanitarias, permisos_sanitarios, delegaciones_sanitarias, accesos_asistenciales.

No se propone agregar estos roles a perfiles.rol comercial — una persona puede trabajar en dos centros con funciones distintas; un rol global no lo representa.

Regla central de autorización (las 7 deben cumplirse conjuntamente)
Identidad autenticada y activa. 2. Asignación sanitaria vigente. 3. Misma red institucional. 4. Acción permitida. 5. Ámbito territorial/establecimiento autorizado. 6. Relación asistencial o concesión específica sobre la persona. 7. Condiciones del documento y finalidad del acceso. Si falta cualquier dato necesario, se deniega — país coincidente o título de administrador no bastan solos.

Puntos centrales de autorización propuestos (nombres provisionales): ambitos_sanitarios_del_actor, puede_operar_establecimiento, puede_acceder_persona, puede_ejecutar_accion_clinica. Conservan el fail-closed de E3 sin llamar a asesores_a_cargo() ni interpretar roles comerciales.

Quién puede hacer qué (resumen)

Administrador territorial: gestión de establecimientos/asignaciones, NO lectura de notas por defecto. Admisión: identidad y agenda mínima. Médico/enfermería: según competencia/establecimiento/vínculo. Coordinación de referencias: el proceso y su resumen necesario. Epidemiología/estadística: datos necesarios para su función, sin acceso clínico irrestricto. Auditor clínico: acceso temporal justificado. Operador técnico: sin permiso clínico ordinario.

Acceso de emergencia: excepcional, limitado en tiempo/alcance, motivo obligatorio, aviso y revisión posterior. Nunca disponible a cuentas comerciales.

Riesgo de convivencia: alto si se reutilizan tablas/policies comerciales — políticas permisivas existentes pueden combinarse y abrir una ruta alternativa de acceso. Mitigación: separación de proyecto; si se comparte proyecto, hay que demostrar que ninguna vista/RPC/trigger/rol privilegiado existente crea una ruta de acceso — un esquema nuevo por sí solo no lo demuestra.

6. Identidad poblacional y expediente longitudinal
Identidad única (objetivo realista)

SP-05 no promete identificar inequívocamente a toda Guatemala desde el día uno. Propone una persona canónica por red del piloto con mecanismos explícitos de deduplicación.

Entidades: personas, identificadores_persona, vinculos_personales (tutor/contacto), identidades_origen (incluye pacientes de EZPayConnect), casos_duplicidad, resoluciones_identidad.

Invariantes: nadie necesita correo/teléfono/cuenta digital/documento oficial para tener un registro; recién nacido o paciente no identificado recibe UUID provisional; no se fusiona automáticamente por nombre/teléfono/similitud; un identificador oficial verificado no puede estar activo para dos personas canónicas en el mismo ámbito de emisión; una colisión abre revisión, no elimina atención; la fusión conserva IDs de origen y referencias históricas; deshacer una fusión debe ser posible y auditado; buscar coincidencias devuelve lo mínimo necesario, sin habilitar enumeración poblacional.

Autorización: admisión propone correcciones; un responsable de identidad resuelve duplicidades; fusiones sensibles requieren segunda revisión; el médico no cambia identidad unilateralmente.

Núcleo clínico común

encuentros, documentos_clinicos, versiones_documento (con hash y motivo de cambio), observaciones_clinicas, problemas_clinicos, ordenes_clinicas, resultados_clinicos.

SOAP/vitales/resultados de EZPayConnect son la base funcional; sus escrituras deberán pasar por el contrato sanitario nuevo, no directamente por los hooks actuales.

Invariantes: un encuentro pertenece a una persona y establecimiento de la misma red; autor viene de la sesión institucional; borradores admiten revisión versionada; nota firmada es inmutable (se corrige con adenda o nueva versión); se distinguen hora clínica declarada / hora del dispositivo / recepción del servidor; firma offline conserva esa procedencia, no se presenta como certificación legal por defecto; nota tardía no modifica retroactivamente una referencia ya enviada.

Riesgo comercial: reutilizar pacientes.medico_id como propietario nacional fragmentaría identidad y permisos; reutilizar expediente_notas con su UPDATE actual impediría el historial de versiones sin cambiar el comportamiento comercial. Propuesta: equivalencias + importación selectiva, sin fusión automática de poblaciones ni escritura simultánea en ambos productos.

7. Arquitectura offline y sincronización

Patrón: almacén local protegido + cola durable de operaciones + reconciliación transaccional en servidor. Requiere: capa local nueva (inicialmente IndexedDB), protocolo de sincronización, procesador de operaciones, pantallas de pendientes/conflictos/recuperación, gestión de dispositivos.

Entidades servidoras: dispositivos_autorizados, habilitaciones_offline, operaciones_sync (con hash de contenido y dependencias), resultados_sync, conflictos_sync, eventos_cambio. Los IDs se generan también offline para referenciar entidades antes de sincronizar.

Protocolo (7 pasos): preparación online (verificar usuario/equipo/establecimiento, descargar solo lo necesario) → captura (dato + operación pendiente en una transacción local) → envío (lotes pequeños, reintentables, con dependencias) → validación (permisos vigentes, formato, versión, invariantes) → aplicación (transacción de servidor idempotente) → acuse (borrar de la cola solo con confirmación durable) → actualización (por cursor del servidor, filtrado por autorización actual).

Repetir mismo ID+contenido → mismo resultado. Reutilizar un ID con contenido distinto se rechaza. Una observación no se aplica antes del encuentro del que depende. El fallo de una operación no invalida las independientes del lote.

Política de conflictos

Signos/observaciones nuevas: se conservan como eventos independientes. Nota firmada: nunca se sobrescribe, requiere adenda/revisión. Borrador compartido: control por versión. Datos demográficos: revisión ante cambios incompatibles. Identidad duplicada: caso de reconciliación, nunca unión automática. Referencia: transición validada contra versión/estado servidor. Vacunación: conservar eventos, detectar doble registro antes de contar dosis. Inventario: no aceptar saldo absoluto offline como verdad central.

No se propone CRDT para notas firmadas ni "última escritura gana" para hechos clínicos — el costo es tener conflictos visibles, el beneficio es no perder información silenciosamente.

Revocación y permisos offline

Habilitación offline de duración corta y explícita; permisos mínimos y datos preseleccionados; al vencer se bloquea acceso ordinario (continúa la contingencia asistencial acordada); al reconectar se reevalúan permisos; operación de actor revocado no se aplica automáticamente, queda en cuarentena para revisión. El reloj del equipo no prueba que una captura ocurrió antes de la revocación.

Persistencia, cifrado y límites

La copia local necesita cifrado, bloqueo por usuario y gestión de claves. IndexedDB puede enfrentar cuotas o pérdida de almacenamiento — no sustituye respaldo. Gate de selección técnica: si las pruebas en equipos rurales muestran pérdida de datos o aislamiento insuficiente, el piloto necesita una app instalada con almacenamiento local administrado (React puede mantenerse como interfaz, esa envoltura sería una pieza adicional). No depender de Background Sync (disponibilidad limitada) — la sincronización en primer plano con estado visible es obligatoria.

Riesgo comercial: compartir origen web o service worker podría mezclar caché, sesiones y actualizaciones. El origen independiente es parte del aislamiento, no cosmético.

8. Referencia y contrarreferencia

Entidades: referencias, versiones_referencia, eventos_referencia, atenciones_referencia, contrarreferencias, concesiones_referencia (paquete clínico permitido al equipo receptor).

Flujo: borrador → enviada → aceptada → atendida → respuesta emitida → cierre por origen. Ramas: rechazada (con motivo), cancelada, no presentada, redirigida (nueva referencia vinculada, conserva la original).

Reglas: origen autorizado crea/envía; destino autorizado acepta/rechaza; solo el equipo que atendió emite la contrarreferencia; origen confirma recepción y plan de seguimiento; aceptar ≠ paciente llegó; cita programada ≠ referencia atendida; enviar no da acceso al historial completo, solo al paquete definido; antes de aceptar, el destino recibe el mínimo para evaluar; adjuntos/resúmenes versionados; cambios concurrentes de estado se validan contra versión.

Offline y urgencias: se puede preparar una referencia offline pero queda pendiente de transmisión, no aceptada hasta confirmación. En urgencias la coordinación por canales institucionales disponibles continúa; el sistema registra la actuación después — una notificación pendiente nunca se interpreta como traslado coordinado.

Encaje: citas (vínculo opcional, no gobiernan estado clínico), chat médico-paciente (informativo, no institucional), comunicación profesional (hilo propio ligado a la referencia), notificaciones (bandeja durable + reintentos, sin transportar datos clínicos). Entidad transversal eventos_salida creada en la misma transacción que el cambio clínico.

Riesgo comercial: reutilizar citas para habilitar acceso automático ampliaría la relación de tratamiento existente — el flujo público usa concesiones explícitas.

9. Auditoría integral e interoperabilidad gradual

Dos registros distintos: eventos_auditoria (¿quién intentó/consiguió acceder, modificar, exportar?) y versiones/procedencia clínica (¿quién produjo este contenido, cuándo, a partir de qué?) — coherente con AuditEvent/Provenance de HL7 sin exigir FHIR completo.

Evento mínimo: red, actor, asignación efectiva, dispositivo, operación, finalidad, recurso/versión, resultado, política aplicada, id de solicitud, tiempo servidor, procedencia online/offline. No se copia el contenido íntegro de notas al log por defecto.

Cobertura de lecturas: RLS no basta por sí sola. Propuesta: sin acceso clínico directo desde el navegador a tablas/vistas/Realtime; toda lectura pasa por la API sanitaria; autorización y registro de entrega preceden a la devolución del contenido; si no puede persistirse la auditoría, la lectura se deniega; descargas por entrega auditable (no URLs firmadas de larga duración); Realtime transmite señales mínimas, el contenido va por la API. Eventos denegados se persisten independientemente de la transacción rechazada.

Escrituras/exportaciones: mutación + evento de auditoría se confirman juntos; exportaciones vía solicitudes_exportacion/artefactos_exportacion con finalidad, filtros, versión, solicitante, aprobador, hash y descargas; no hay exportación poblacional genérica para todo administrador territorial.

Integridad: logs acumulativos con permisos separados, sellos periódicos, copia a almacenamiento independiente con retención acordada. Una cadena de hashes en la misma base no protege contra quien controla toda la base — hace falta independencia de custodia. Offline: accesos locales se registran y envían al reconectar, sin garantía absoluta si se pierde/manipula el dispositivo antes.

Terminologías desde el inicio

sistemas_codificacion, conceptos_clinicos, diagnosticos_encuentro (texto original + código), productos_farmaceuticos (id interno estable), identificadores_producto, equivalencias_catalogo.

Decisiones: CIE-10 con versión aprobada para el piloto; mantener texto original + código (no convertir automáticamente narrativas históricas en diagnósticos confirmados); captura sin código permitida, pendiente de codificación para cierre estadístico; no identificar medicamentos solo por nombre comercial; producto normalizado y lote son entidades distintas; equivalencias revisadas, no emparejamiento automático por semejanza.

Ruta posterior a FHIR: preservar desde el inicio IDs, unidades, códigos, versiones y procedencia, para mapear después a recursos FHIR. No prometer compatibilidad FHIR solo porque el backend entregue JSON.

Riesgo comercial: ampliar super_admin/auditoria_logs/exportaciones comerciales para incluir población pública produciría accesos transversales.

10. Programas P1 y reporte sanitario

Comparten persona, encuentro, observaciones, catálogos, autorización, auditoría y sincronización — no crean historiales paralelos por programa.

Programa	Entidades nuevas	Invariantes clave
Vacunación	eventos_vacunacion, esquemas_vacunacion, lotes_biologicos, incidencias_vacunacion	Separar dosis administrada de antecedente referido; correcciones como eventos vinculados
Prenatal	episodios_gestacion, controles_prenatales, riesgos_gestacion, cierres_gestacion	Conservar método/fecha de estimación gestacional; alertas versionadas
Crecimiento infantil	evaluaciones_crecimiento, referencias_antropometricas, seguimientos_nutricionales	Medidas crudas preservadas; percentil inválido si fecha de nacimiento es incierta
Crónicos	inscripciones_programa, planes_seguimiento, metas_clinicas, controles_cronicos	Condición activa/resuelta explícita; un programa no crea otra persona
Reporte sanitario	definiciones_reporte, mapeos_reporte, cortes_reporte, validaciones_reporte, envios_reporte	Un corte enviado es inmutable; corrección por nueva versión

Reporte durante el piloto: producir primero los instrumentos concretos acordados con SIGSA o la autoridad receptora — no asumir una API disponible, puede empezar con exportación validada + registro de envío. Cada reporte debe distinguir fecha clínica vs recepción tardía, individual vs agregado, establecimiento de atención vs residencia, duplicados/anulaciones/correcciones, pendientes de codificación, confirmación técnica vs aceptación institucional.

Dependencia de cartera: si el piloto cubre vacunación o prenatal, esos módulos deben estar listos antes de activar ese servicio — no diferirlos mientras se afirma cobertura de atención primaria integral.

Riesgo comercial: reutilizar métricas de publicidad/campañas/reportes de país mezclaría finalidades y permisos.

11. Complementos P0: farmacia y continuidad

Farmacia (si forma parte del piloto): ubicaciones_stock, lotes, movimientos_stock, transferencias_stock, dispensaciones_publicas. Invariantes: no reemplazar existencias sin movimiento+motivo; transferencia distingue despacho/recepción; dispensación pública no genera comisión comercial; vencido/bloqueado no dispensable ordinariamente; ajustes requieren permiso y evidencia. Offline: asignar una ubicación física a un dispositivo responsable (no se puede garantizar saldo global exacto con varios equipos desconectados sobre el mismo stock).

Continuidad y capacidad: el proyecto separado reduce impacto comercial pero no acredita disponibilidad. Antes de operar se necesitan objetivos acordados de: tiempo máximo de recuperación, pérdida tolerable de datos sincronizados, duración offline prevista, conservación/recuperación de capturas no sincronizadas, concurrencia y volumen de sincronización al reconectar. La prueba de recuperación debe abarcar base + archivos + identidad/configuración + claves — restaurar solo tablas no recupera el servicio clínico.

12. Secuencia de entrega y criterios de salida
Etapa	Resultado	Bloquea
0. Contrato del piloto	Establecimientos, cartera, reportes, autoridad, offline y continuidad definidos	Todo lo demás
1. Frontera e identidad institucional	Proyecto independiente, red, territorio, asignaciones	Toda autorización
2. Corte vertical offline	Persona provisional + encuentro + observación sincronizan correctamente	Debe probarse antes de construir todas las pantallas clínicas
3. Expediente ambulatorio	Registro, SOAP, vitales, diagnósticos, documentos trazables	El expediente
4. Referencias y coordinación	Origen→destino→respuesta comprobables	Depende de 1-3
5. Cartera y reporte	Programas incluidos y salidas institucionales	Depende del núcleo común
6. Arranque controlado	Operación verificable en establecimientos seleccionados	—

En paralelo una vez estabilizadas 1-2: catálogos y mapeos de reporte, formularios de programas, flujo de referencias, procedimientos de recuperación, preparación de datos y revisión de duplicidades. La auditoría y la sincronización NO son trabajo que se agrega al final.

Gates antes del piloto con datos reales
Aislamiento (usuarios comerciales no acceden a datos públicos). 2. Territorio (asignación de distrito no cruza límites; cambiar adscripción no altera historia). 3. Identidad (duplicados/fusiones sin perder documentación). 4. Offline (reintentos, caída durante envío, cola incompleta, conflictos sin duplicar ni descartar). 5. Revocación (dispositivo/actor revocado no aplica cambios automáticos). 6. Referencias (no confundir enviada/aceptada/atendida/respondida). 7. Auditoría (lecturas/versiones/exportaciones reconstruibles, incluidos fallos del registro). 8. Recuperación (restauración integral demostrada). 9. Reporte (una muestra aceptada por responsables sanitarios). 10. Cartera (cada servicio activado con recorrido y contingencia completos).
13. Riesgos para el SaaS comercial: resumen por pieza
Pieza	Riesgo si se incorpora al esquema actual
Territorio	Cambiar la semántica de pais_id y ampliar scopes existentes
Roles	Otorgar acceso público mediante super_admin/admin_pais/membresías privadas
Personas	Mezclar población pública/privada, búsquedas cruzadas
Expediente	Cambiar escrituras/triggers clínicos existentes al introducir inmutabilidad
Offline	Compartir caché, sesión y actualizaciones del service worker
Referencias	Usar citas como apertura implícita de acceso a información
Auditoría	Vía transversal de lectura/exportación mediante herramientas administrativas
Programas	Exponer información sanitaria por reportes comerciales de país
Catálogos/farmacia	Alterar matching, precios, despacho y comisiones existentes
Infraestructura	Competir por conexiones, Realtime, almacenamiento, ventanas de recuperación

La separación propuesta evita muchas rutas accidentales, pero sigue requiriendo seguridad propia — no convierte automáticamente el nuevo proyecto en seguro.

Recomendación para la revisión

Cuatro acuerdos centrales:

Separar el dominio público y su autoridad del comercial.
Construir primero territorio, identidad, expediente versionado y auditoría.
Validar offline con un recorrido clínico pequeño antes de ampliar funcionalidad.
Activar únicamente la cartera cuyos flujos, referencias y reportes estén completos.

Las decisiones que más condicionan esfuerzo y viabilidad: separación de proyecto, dispositivos y duración offline, participación ambulatoria de hospitales, cartera exacta e instrumentos de reporte.
