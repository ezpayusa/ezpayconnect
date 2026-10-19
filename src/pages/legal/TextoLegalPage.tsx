import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { Link } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'
import { textoLegalPorCodigo, type CodigoTextoLegal } from '@/legal'

// GL-02: páginas públicas de los textos legales (/terminos, /privacidad, /consentimiento-salud,
// /condiciones-profesionales). El texto sale de src/legal (el mismo .md cuyo md5 guarda la base), nunca de la URL.
// Seguridad: markdown sin HTML crudo — sin rehype-raw y con skipHtml, así un <script> o un <img onerror> en el .md
// no llega al DOM. Este componente y react-markdown viven solo en el chunk lazy de la ruta (ver tmp/gl02_front/notas.md).

// Estilos del markdown con el tema oficial (sin ThemeProvider de tenant): la app no tiene @tailwindcss/typography.
const CLASES_MARKDOWN = [
  'text-sm sm:text-base leading-relaxed text-[#1a2a3a] break-words',
  '[&_h2]:text-xl [&_h2]:sm:text-2xl [&_h2]:font-bold [&_h2]:mt-2 [&_h2]:mb-4',
  '[&_h3]:text-lg [&_h3]:font-semibold [&_h3]:mt-8 [&_h3]:mb-3 [&_h3]:text-[#1E5C8E]',
  '[&_h4]:font-semibold [&_h4]:mt-6 [&_h4]:mb-2',
  '[&_p]:my-3',
  '[&_ul]:list-disc [&_ul]:pl-6 [&_ul]:my-3 [&_ol]:list-decimal [&_ol]:pl-6 [&_ol]:my-3 [&_li]:my-1',
  '[&_a]:text-[#1E5C8E] [&_a]:underline',
  '[&_strong]:font-semibold',
  '[&_blockquote]:border-l-4 [&_blockquote]:border-gray-300 [&_blockquote]:pl-4 [&_blockquote]:text-gray-600',
  '[&_hr]:my-8 [&_hr]:border-gray-200',
  '[&_table]:w-full [&_table]:border-collapse [&_table]:text-sm',
  '[&_th]:border [&_th]:border-gray-300 [&_th]:bg-gray-100 [&_th]:px-3 [&_th]:py-2 [&_th]:text-left',
  '[&_td]:border [&_td]:border-gray-300 [&_td]:px-3 [&_td]:py-2 [&_td]:align-top',
].join(' ')

/** Renderiza markdown sin HTML crudo. Las tablas van envueltas en un contenedor con scroll horizontal. */
export function MarkdownLegal({ contenido }: { contenido: string }) {
  return (
    <div className={CLASES_MARKDOWN}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        skipHtml
        components={{
          table: ({ node: _node, ...props }) => (
            <div className="overflow-x-auto my-4">
              <table {...props} />
            </div>
          ),
        }}
      >
        {contenido}
      </ReactMarkdown>
    </div>
  )
}

export default function TextoLegalPage({ codigo }: { codigo: CodigoTextoLegal }) {
  const texto = textoLegalPorCodigo(codigo)

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="mx-auto max-w-3xl px-4 py-6 sm:px-6 sm:py-10">
        <Link to="/" className="inline-flex items-center text-sm text-[#1E5C8E] hover:underline mb-6">
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Link>
        {texto ? (
          <article className="rounded-lg bg-white p-4 shadow-sm sm:p-8">
            <header className="mb-6 border-b border-gray-200 pb-4">
              <h1 className="text-2xl font-bold text-[#1a2a3a]">{texto.titulo}</h1>
              <p className="mt-1 text-sm text-muted-foreground">Versión {texto.version} (provisional)</p>
            </header>
            <MarkdownLegal contenido={texto.contenido} />
          </article>
        ) : (
          <p className="text-sm text-muted-foreground">Texto no disponible.</p>
        )}
      </div>
    </div>
  )
}
