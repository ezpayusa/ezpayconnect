import { Component, type ErrorInfo, type ReactNode } from 'react'
import * as Sentry from '@sentry/react'
import { esChunkError, recargarPorChunkObsoleto } from '@/lib/chunk-reload'

interface Props {
  children: ReactNode
}
interface State {
  hasError: boolean
}

// ErrorBoundary global. Regla innegociable:
//  - error de chunk obsoleto → recarga controlada (mismo contador que los listeners, máx 2/sesión).
//  - CUALQUIER otro error → fallback visible ("Algo salió mal" + Recargar). NUNCA recarga automática
//    (un error de render determinístico + reload automático = loop infinito).
export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false }

  static getDerivedStateFromError(): State {
    return { hasError: true }
  }

  componentDidCatch(error: unknown, errorInfo: ErrorInfo): void {
    const msg = (error as { message?: unknown })?.message ?? error
    if (esChunkError(msg)) {
      // Chunk obsoleto: recarga controlada (bajo el tope) o no-op (sobre el tope → queda el fallback).
      // NO es un bug: no se reporta a Sentry.
      recargarPorChunkObsoleto()
      return
    }
    Sentry.captureException(error, {
      contexts: { react: { componentStack: errorInfo.componentStack } },
    })
    console.error('[ErrorBoundary] error de render no recuperable:', msg)
  }

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        <div
          style={{
            minHeight: '100vh',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 16,
            padding: 24,
            textAlign: 'center',
            fontFamily: 'system-ui, sans-serif',
            color: '#1a2a3a',
          }}
        >
          <h1 style={{ fontSize: 20, fontWeight: 700, margin: 0 }}>Algo salió mal</h1>
          <p style={{ color: '#6b7280', margin: 0 }}>
            Ocurrió un error inesperado. Podés recargar la página.
          </p>
          <button
            onClick={() => window.location.reload()}
            style={{
              padding: '10px 20px',
              background: '#1E5C8E',
              color: 'white',
              border: 'none',
              borderRadius: 8,
              cursor: 'pointer',
              fontWeight: 600,
            }}
          >
            Recargar
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
