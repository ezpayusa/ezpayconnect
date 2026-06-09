# 🧪 Testing Manual - Flujo de Citas End-to-End

## Pre-requisitos
- [ ] Build de Vercel en estado "Ready" (nuevo bundle activo)
- [ ] Service Worker actualizado (recargar página 2 veces con Ctrl+F5)
- [ ] Supabase Edge Functions deployadas (30 funciones activas)
- [ ] 1 cuenta de paciente registrada
- [ ] 1 cuenta de clínica registrada
- [ ] Al menos 1 médico vinculado a la clínica

---

## Test 1: Paciente agenda cita CON doctor

### Paso 1.1 - Login como paciente
1. Ir a `https://ezpayconnect.vercel.app`
2. Iniciar sesión con cuenta de paciente
3. Verificar: `user_metadata.role === 'paciente'`
4. Abrir DevTools → Console, buscar: `=== EZPAYCONNECT PROD BUILD ===`

### Paso 1.2 - Agendar cita
1. Ir a "Agendar Cita"
2. Seleccionar una **clínica** (obligatorio, no debe haber "Sin preferencia")
3. Seleccionar un **médico** (obligatorio para este test)
4. Seleccionar fecha futura
5. Seleccionar hora disponible
6. Ingresar motivo de consulta
7. Click en "Confirmar"

### Paso 1.3 - Verificar estado inicial
**Esperado:** La cita se crea con `estado = 'agendada'`
```sql
-- Verificar en Supabase SQL Editor
SELECT id, estado, medico_id, clinica_id, paciente_id, fecha, hora_inicio 
FROM citas 
ORDER BY created_at DESC 
LIMIT 1;
```

### Paso 1.4 - Verificar notificación push
**Esperado:**
- [ ] El paciente recibe notificación push de "Cita agendada"
- [ ] La notificación tiene título, mensaje e icono
- [ ] Click en notificación abre la app

### Paso 1.5 - Verificar en panel del paciente
1. Ir a "Mis Citas"
2. Verificar que la cita aparece con estado "Agendada"
3. Verificar que muestra nombre del médico y clínica

---

## Test 2: Paciente agenda cita SIN doctor (solicitud)

### Paso 2.1 - Agendar sin médico
1. Repetir pasos 1.1-1.2 pero **SIN seleccionar médico**
2. Click en "Confirmar"

### Paso 2.2 - Verificar estado
**Esperado:** La cita se crea con `estado = 'solicitada'`
```sql
SELECT id, estado, medico_id, clinica_id 
FROM citas 
ORDER BY created_at DESC 
LIMIT 1;
```

---

## Test 3: Clínica confirma cita solicitada

### Paso 3.1 - Login como clínica
1. Abrir navegador en modo incógnito
2. Ir a `https://ezpayconnect.vercel.app`
3. Login con `doctor@prueba.com` / `Doctor123!`
4. Verificar que aparece el selector de clínica (si tiene múltiples)

### Paso 3.2 - Ver cita entrante
1. Ir a "Citas"
2. Verificar que aparece la cita del Test 2 (estado "Solicitada")
3. Verificar datos: paciente, fecha, hora, motivo

### Paso 3.3 - Asignar médico y confirmar
1. Seleccionar médico del dropdown
2. Click en "Confirmar Cita"
3. Verificar mensaje de éxito

### Paso 3.4 - Verificar estado actualizado
```sql
SELECT id, estado, medico_id 
FROM citas 
WHERE estado = 'confirmada' 
ORDER BY updated_at DESC 
LIMIT 1;
```
**Esperado:** `estado = 'confirmada'`, `medico_id` asignado

### Paso 3.5 - Verificar notificación al paciente
**Esperado:** El paciente recibe:
- [ ] Notificación push: "Cita confirmada"
- [ ] Mensaje: "Tu cita para el [fecha] a las [hora] ha sido confirmada"
- [ ] Notificación in-app en el portal del paciente

---

## Test 4: Clínica rechaza cita

### Paso 4.1 - Crear nueva cita
1. Como paciente, crear otra cita (con o sin médico)

### Paso 4.2 - Rechazar como clínica
1. Como clínica, ir a "Citas"
2. Encontrar la cita recién creada
3. Click en "Cancelar Cita"
4. Verificar mensaje de éxito

### Paso 4.3 - Verificar estado
```sql
SELECT id, estado 
FROM citas 
WHERE estado = 'cancelada' 
ORDER BY updated_at DESC 
LIMIT 1;
```
**Esperado:** `estado = 'cancelada'`

### Paso 4.4 - Verificar notificación
**Esperado:** El paciente recibe:
- [ ] Notificación push: "Cita cancelada"
- [ ] Mensaje indicando que fue cancelada

---

## Test 5: Multi-clínica

### Paso 5.1 - Verificar selector
1. Login como clínica con acceso a múltiples clínicas
2. Verificar que aparece dropdown de selector de clínica
3. Cambiar entre clínicas
4. Verificar que las citas cambian según la clínica seleccionada

### Paso 5.2 - Verificar aislamiento
```sql
-- Contar citas por clínica
SELECT clinica_id, COUNT(*) 
FROM citas 
WHERE estado IN ('solicitada', 'agendada', 'confirmada')
GROUP BY clinica_id;
```
**Esperado:** Cada clínica solo ve sus propias citas

---

## Test 6: Service Worker y Cache

### Paso 6.1 - Verificar SW activo
```javascript
// En DevTools Console
navigator.serviceWorker.ready.then(reg => {
  console.log('SW activo:', reg.active?.scriptURL);
  console.log('Scope:', reg.scope);
});
```

### Paso 6.2 - Verificar push subscription
```javascript
// En DevTools Console
navigator.serviceWorker.ready.then(reg => {
  reg.pushManager.getSubscription().then(sub => {
    console.log('Push subscription:', sub ? 'ACTIVA' : 'NO HAY');
    if (sub) console.log('Endpoint:', sub.endpoint.slice(0, 50) + '...');
  });
});
```

### Paso 6.3 - Verificar en Supabase
```sql
SELECT user_id, created_at 
FROM push_subscriptions 
ORDER BY created_at DESC 
LIMIT 5;
```

---

## Checklist Final

### Funcionalidad
- [ ] Paciente puede agendar cita con doctor
- [ ] Paciente puede agendar cita sin doctor (solicitud)
- [ ] Clínica ve citas de todas sus clínicas
- [ ] Clínica puede cambiar entre clínicas
- [ ] Clínica puede confirmar cita
- [ ] Clínica puede rechazar/cancelar cita
- [ ] Estados se actualizan correctamente en BD

### Notificaciones
- [ ] Push subscription se crea automáticamente
- [ ] Paciente recibe notificación al agendar
- [ ] Paciente recibe notificación al confirmar
- [ ] Paciente recibe notificación al cancelar
- [ ] Notificaciones tienen icono y funcionan al click

### UI
- [ ] No hay errores de íconos en consola (lucide-react)
- [ ] Selector de clínica funciona correctamente
- [ ] Fechas y horas se muestran en formato correcto
- [ ] No hay páginas en blanco o crashes

---

## En caso de errores

### Error: "No se encontró la clínica"
- Verificar que `obtener_clinica_usuario` retorna datos
- Verificar que el usuario está en `medico_clinicas` o `clinicas.doctor_id`

### Error: "No se pudo crear la cita"
- Revisar console logs del navegador
- Verificar que `crear_cita` RPC existe y funciona
- Verificar tipos de datos (UUID para clinica_id, BIGINT para paciente_id)

### Error: No llegan notificaciones push
- Verificar que VAPID keys están configuradas en Supabase
- Verificar que `enviar-push` edge function funciona
- Revisar logs de Supabase Functions

### Error: Iconos rotos
- Verificar versión de lucide-react: `npm ls lucide-react`
- Buscar en consola: `Warning: React.createElement: type is invalid`
- Reemplazar ícono problemático por alternativa

---

## Comandos útiles

```bash
# Verificar edge functions deployadas
supabase functions list

# Ver logs de una función
supabase functions logs enviar-push --tail

# Forzar recarga del SW
# En DevTools → Application → Service Workers → Unregister → Recargar página
```
