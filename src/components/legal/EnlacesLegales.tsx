import { Fragment } from 'react'
import { textosPara, type ParaTextosLegales } from './CasillaTextosLegales'

// GL-02: links a los textos legales para el pie de los logins. Solo navegación: sin estado ni llamadas a la base. Los
// textos, títulos y rutas salen del catálogo (textosPara); los links abren en otra pestaña, igual que en la casilla.

export function EnlacesLegales({ para, className }: { para: ParaTextosLegales; className?: string }) {
  const textos = textosPara(para)
  return (
    <nav aria-label="Textos legales" className={`text-center text-xs text-muted-foreground ${className ?? ''}`}>
      {textos.map((t, i) => (
        <Fragment key={t.codigo}>
          {i > 0 && ' · '}
          <a href={t.ruta} target="_blank" rel="noopener noreferrer" className="hover:underline">
            {t.titulo}
            <span className="sr-only"> (se abre en otra pestaña)</span>
          </a>
        </Fragment>
      ))}
    </nav>
  )
}
