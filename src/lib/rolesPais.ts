// Roles cuyo perfil EXIGE país.
//
// Es el espejo en el front de ROLES_QUE_EXIGEN_PAIS de supabase/functions/crear-empleado/index.ts,
// que es quien decide de verdad (rechaza con 400 antes de crear el usuario). Lo respaldan en la base
// los CHECK vivos admin_pais_requiere_pais (mig 216) y comercial_requiere_pais (mig 263).
//
// rolesPais.test.ts lee la edge y fija que las dos listas sean iguales: al agregar un rol que exige
// país, hay que agregarlo en la edge Y acá, o el test se pone rojo.

export const ROLES_QUE_EXIGEN_PAIS = ['admin_pais', 'asesor_comercial', 'supervisor_comercial'] as const

export function rolExigePais(rol: string | null | undefined): boolean {
  return !!rol && (ROLES_QUE_EXIGEN_PAIS as readonly string[]).includes(rol)
}
