// Ruteo de las cuentas de empresa (cuentas_proveedor). Funciones puras, sin react/router.
//
// Es el ÚNICO lugar que decide a qué panel va una cuenta de empresa después del login, y qué link de
// entrada le corresponde a cada tipo de empresa. Lo usan los tres logins (ProveedorLogin, FarmaciaLogin
// y LabLogin): así cualquier cuenta llega a su panel entre por donde entre.
//
// La edge invitar-staff-proveedor tiene una copia de rutaLoginEmpresa (Deno no importa src/), y un test
// fija que coincidan.
//
// Los tipos válidos salen del CHECK empresas_proveedoras_tipo_check.

export type TipoEmpresa = 'farmacia' | 'laboratorio_clinico' | 'laboratorio_farmaceutico' | 'empresa_afin'

// El orden importa: el visitador va a su PWA aunque su empresa sea una farmacia o un laboratorio
// clínico (VisitadorPrivateRoute no mira el tipo). El repartidor, solo si la empresa es farmacia: es
// lo que exige RepartidorPrivateRoute.
export function rutaHomeEmpresa(tipo: string | null | undefined, rol: string | null | undefined): string {
  if (rol === 'visitador_medico') return '/visitador'
  if (tipo === 'farmacia' && rol === 'delivery') return '/repartidor'
  if (tipo === 'farmacia') return '/farmacia/dashboard'
  if (tipo === 'laboratorio_clinico') return '/laboratorio/dashboard'
  return '/proveedor/dashboard'
}

export function rutaLoginEmpresa(tipo: string | null | undefined): string {
  if (tipo === 'farmacia') return '/farmacia/login'
  if (tipo === 'laboratorio_clinico') return '/laboratorio/login'
  return '/proveedor/login'
}
