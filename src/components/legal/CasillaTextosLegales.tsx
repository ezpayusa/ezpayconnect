import { Fragment, useId } from 'react'
import { TEXTOS_LEGALES, type TextoLegal } from '@/legal'

// GL-02: casilla única de aceptación de los textos legales para las altas. Solo UI: no llama a ninguna RPC; el
// formulario que la usa bloquea el envío mientras checked = false y registra la aceptación con aceptarTextos().
// Los documentos salen de TEXTOS_LEGALES por aplica_a (los de 'todos' primero, en el orden del catálogo, y después
// los del grupo); los links abren en otra pestaña para no perder lo cargado en el formulario.

export type ParaTextosLegales = 'paciente' | 'profesional'

/** D-4: la cuenta de paciente la abre un adulto o el representante legal del paciente. */
export const DECLARACION_MAYORIA_EDAD = 'Declaro que soy mayor de 18 años o que actúo como representante legal del paciente.'

export function textosPara(para: ParaTextosLegales): TextoLegal[] {
  const todos = TEXTOS_LEGALES.filter((t) => t.aplica_a.includes('todos'))
  const grupo = TEXTOS_LEGALES.filter((t) => !t.aplica_a.includes('todos') && t.aplica_a.includes(para))
  return [...todos, ...grupo]
}

interface Props {
  para: ParaTextosLegales
  checked: boolean
  onChange: (checked: boolean) => void
  disabled?: boolean
  id?: string
}

export function CasillaTextosLegales({ para, checked, onChange, disabled = false, id }: Props) {
  const idAuto = useId()
  const idInput = id ?? `textos-legales-${idAuto}`
  const textos = textosPara(para)

  return (
    <div className="flex items-start gap-2">
      <input
        type="checkbox"
        id={idInput}
        checked={checked}
        disabled={disabled}
        onChange={(e) => {
          if (!disabled) onChange(e.target.checked)
        }}
        className="mt-0.5 h-4 w-4 shrink-0 accent-[#1E5C8E] disabled:cursor-not-allowed"
      />
      <label htmlFor={idInput} className="text-sm leading-snug text-[#1a2a3a]">
        Leí y acepto{' '}
        {textos.map((t, i) => (
          <Fragment key={t.codigo}>
            {i > 0 && (i === textos.length - 1 ? ' y ' : ', ')}
            <a
              href={t.ruta}
              target="_blank"
              rel="noopener noreferrer"
              className="text-[#1E5C8E] underline"
            >
              {t.titulo}
              <span className="sr-only"> (se abre en otra pestaña)</span>
            </a>
          </Fragment>
        ))}
        .{para === 'paciente' && <> {DECLARACION_MAYORIA_EDAD}</>}
      </label>
    </div>
  )
}
