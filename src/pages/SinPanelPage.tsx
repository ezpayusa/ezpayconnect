import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'

// Destino de los roles que no tienen (todavía) una superficie propia, y de los que no conocemos.
//
// POR QUE EXISTE: antes esos roles aterrizaban en /dashboard, el panel médico, con el menú vacío
// y sin salida. Esta pantalla no lee NADA de la base — ni una query — así que es correcta para un
// rol del que no sabemos qué tiene derecho a ver, que es exactamente cuando menos hay que adivinar.
// Lo único que ofrece es cerrar sesión.
export default function SinPanelPage() {
  const { perfil, logout } = useAuth()
  const navigate = useNavigate()

  const salir = async () => {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-md rounded-lg bg-white p-6 shadow text-center">
        <h1 className="text-lg font-semibold text-gray-900">Tu cuenta todavía no tiene un panel asignado</h1>
        <p className="mt-2 text-sm text-gray-600">
          El acceso quedó creado correctamente, pero el rol{' '}
          <span className="font-mono text-gray-800">{perfil?.rol || 'sin rol'}</span> aún no tiene una
          pantalla propia en esta versión. Escribile a quien administra tu cuenta para que te asignen
          el panel que corresponde.
        </p>
        <button
          type="button"
          onClick={salir}
          className="mt-5 w-full rounded-md bg-[#1E5C8E] px-4 py-2 text-sm font-medium text-white hover:bg-[#17496f]"
        >
          Cerrar sesión
        </button>
      </div>
    </div>
  )
}
