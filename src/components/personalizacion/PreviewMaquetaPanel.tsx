// Maqueta de vista previa AISLADA. Recibe los valores del draft (pickers) y los pinta con estilos
// INLINE LOCALES. NO importa ni toca TenantThemeContext / TenantThemeProvider, NO setea CSS vars en
// :root, NO muta el tema real del panel. Es una caja encapsulada — el panel real solo cambia tras
// aprobación. Cambiar los pickers acá jamás afecta la app fuera de este componente.
// NOTA: color_fondo NO se previsualiza porque el panel real aún no lo cablea (fase conservadora);
// mostrarlo prometería un cambio que no ocurre tras aprobar. El área de contenido usa un neutro fijo.
export function PreviewMaquetaPanel({
  primario, secundario, logoUrl,
}: { primario: string; secundario: string; logoUrl: string }) {
  return (
    <div className="rounded-lg border border-slate-200 overflow-hidden shadow-sm w-full max-w-[280px]">
      <div className="flex" style={{ height: 190 }}>
        {/* Mini sidebar (fondo oscuro fijo, como el real; el logo y el item activo son del draft) */}
        <div className="w-[46%] p-2 space-y-1.5" style={{ backgroundColor: '#1a2a3a' }}>
          <div className="flex items-center gap-2 mb-2">
            <img src={logoUrl} alt="" className="h-6 w-6 rounded object-contain shrink-0 bg-white/10" />
            <span className="text-white text-[10px] font-bold truncate">Mi Panel</span>
          </div>
          <div className="text-white text-[9px] rounded px-2 py-1 font-medium" style={{ backgroundColor: primario }}>
            Inicio
          </div>
          <div className="text-white/70 text-[9px] px-2 py-1">Sección</div>
          <div className="text-white/70 text-[9px] px-2 py-1">Sección</div>
        </div>
        {/* Área de contenido: neutro FIJO — color_fondo aún no se cablea en el panel real */}
        <div className="flex-1 p-2.5 space-y-1.5" style={{ backgroundColor: '#f9fafb' }}>
          <div className="h-2.5 w-20 rounded" style={{ backgroundColor: primario }} />
          <div className="h-2 w-14 rounded" style={{ backgroundColor: secundario }} />
          <div className="h-2 w-24 rounded bg-black/10" />
          <div className="h-2 w-16 rounded bg-black/10" />
        </div>
      </div>
      <div className="text-[9px] text-center text-muted-foreground py-1 border-t border-slate-100 bg-white">
        Vista previa — no afecta el panel real
      </div>
    </div>
  )
}
