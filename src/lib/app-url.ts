// URL canónica de la app en producción. Dominio único que se conserva.
//
// DECISIÓN: constante en código, NO variable de entorno. El patrón
// `import.meta.env.X || ''` produce links rotos en silencio cuando la var falta.
// La constante viaja con el commit y es visible en el diff/review.
//
// Supabase Auth: Site URL = https://med.ezpayconnect.com, Redirect URL med.*/** →
// med.ezpayconnect.com es el canónico. NO usar https://ezpayconnect.vercel.app
// (ese proyecto de Vercel se va a borrar).
export const APP_URL = 'https://med.ezpayconnect.com'
