// Marca oficial EZPayConnect, FIJA. Va en los footers de los sidebars de Clínica y Proveedor,
// aunque el tenant tenga su propio logo/colores arriba. Es marca EZPay, NO del tenant:
// por eso hardcodea '/ezpayconnect_icono.svg' y NUNCA llama useTema() ni lee el logo del tenant.
// Pensado para fondo oscuro (#1a2a3a de los sidebars): texto tenue text-white/40.
export function PoweredBy({ className = '' }: { className?: string }) {
  return (
    <div className={`flex items-center justify-center gap-1.5 text-white/40 ${className}`}>
      <img src="/ezpayconnect_icono.svg" alt="" className="h-4 w-4 object-contain opacity-70" />
      <span className="text-[10px] font-medium tracking-wide">Powered by EZPayConnect</span>
    </div>
  )
}
