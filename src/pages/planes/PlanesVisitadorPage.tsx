import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { MapPin, Check, ArrowRight, Navigation, CalendarCheck, ClipboardCheck, BarChart3 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { usePaisFiltro } from '@/hooks/usePaisFiltro';
import { useProveedorAuth } from '@/proveedor/hooks/useProveedorAuth';
import { paisOperativo } from '@/proveedor/lib/compraPlanVisitador';
import { getBanderaPais } from '@/lib/planes-utils';
import { formatearMonto } from '@/lib/moneda';

// Fila de catalogo_planes_visitador_publico (mig 362): solo lo que hoy se puede comprar (mismo criterio que
// solicitar_compra_plan_visitador). Funciona sin sesión, así que la landing no lee planes_base ni planes_configuracion.
interface PlanCatalogo {
  pais_codigo: string;
  pais_nombre: string;
  config_id: string;
  plan_nombre: string;
  plan_descripcion: string | null;
  precio: number;
  moneda: string;
  visitas: number;
  duracion_dias: number;
}

// getBanderaPais tipa el código con su lista cerrada; un código fuera de la lista cae en su bandera genérica.
const bandera = (codigo: string) => getBanderaPais(codigo as Parameters<typeof getBanderaPais>[0]);

const ERROR_CARGA = 'No pudimos cargar los planes. Intente de nuevo en unos minutos.';

// Solo se describe lo que el módulo de visitas hace hoy.
const FUNCIONES_REALES = [
  'Agenda de visitas a médicos',
  'Aprobación del supervisor',
  'Check-in y check-out con evidencia',
  'Ruta del día',
  'Reporte de visitas',
];

export default function PlanesVisitadorPage() {
  const { paisId: paisPerfil } = usePaisFiltro();
  const { user: userProveedor, cuenta, empresa } = useProveedorAuth();
  const { user } = useAuth();
  const navigate = useNavigate();

  const [planes, setPlanes] = useState<PlanCatalogo[]>([]);
  const [cargando, setCargando] = useState(true);
  const [errorCarga, setErrorCarga] = useState(false);
  const [paisElegido, setPaisElegido] = useState<string | null>(null);
  const [planCheckout, setPlanCheckout] = useState<PlanCatalogo | null>(null);

  // País de la sesión: el de la cuenta proveedora (private.mi_pais) o, si no, el del perfil. Es un uuid de
  // configuracion_pais y el catálogo se identifica por código: hay que resolverlo (comparar el uuid contra el código
  // era el bug que dejaba todos los planes en "No disponible").
  const paisSesionId = paisOperativo(cuenta, empresa) ?? paisPerfil ?? null;
  const [codigoSesion, setCodigoSesion] = useState<{ id: string; codigo: string | null } | null>(null);
  const resolviendoPais = !!paisSesionId && codigoSesion?.id !== paisSesionId;

  useEffect(() => {
    let cancelado = false;
    const fallo = (err: unknown) => {
      console.error(err);
      setErrorCarga(true);
      setPlanes([]);
      setCargando(false);
    };
    supabase.rpc('catalogo_planes_visitador_publico').then(({ data, error }) => {
      if (cancelado) return;
      if (error) return fallo(error);
      setPlanes(((data as PlanCatalogo[] | null) ?? []).map((p) => ({ ...p, precio: Number(p.precio) })));
      setCargando(false);
    }, (err: unknown) => {
      if (!cancelado) fallo(err);
    });
    return () => {
      cancelado = true;
    };
  }, []);

  useEffect(() => {
    if (!paisSesionId) return;
    let cancelado = false;
    supabase
      .from('configuracion_pais')
      .select('codigo')
      .eq('id', paisSesionId)
      .maybeSingle()
      .then(
        ({ data }) => {
          if (!cancelado) setCodigoSesion({ id: paisSesionId, codigo: (data as { codigo?: string } | null)?.codigo ?? null });
        },
        // sin código resoluble se usa el primer país del catálogo
        () => {
          if (!cancelado) setCodigoSesion({ id: paisSesionId, codigo: null });
        }
      );
    return () => {
      cancelado = true;
    };
  }, [paisSesionId]);

  // Países del selector: solo los que tienen algo comprable (el orden es el de la RPC, por código).
  const paises = useMemo(() => {
    const vistos = new Map<string, string>();
    for (const p of planes) if (!vistos.has(p.pais_codigo)) vistos.set(p.pais_codigo, p.pais_nombre);
    return [...vistos].map(([codigo, nombre]) => ({ codigo, nombre }));
  }, [planes]);

  // País inicial: el de la sesión si está en el catálogo; si no, el primero del catálogo.
  const codigoInicial =
    codigoSesion?.codigo && paises.some((p) => p.codigo === codigoSesion.codigo) ? codigoSesion.codigo : paises[0]?.codigo;
  const paisSeleccionado = paisElegido ?? codigoInicial ?? null;
  const planesPais = planes.filter((p) => p.pais_codigo === paisSeleccionado);
  const loading = cargando || resolviendoPais;
  const esProveedor = !!cuenta;

  return (
    <div className="min-h-screen bg-gradient-to-b from-amber-50 to-white">
      {/* Header */}
      <div className="bg-gradient-to-r from-orange-600 to-amber-700 text-white py-16">
        <div className="container mx-auto px-4 text-center">
          <div className="flex justify-center mb-4">
            <MapPin className="h-16 w-16 text-amber-200" />
          </div>
          <h1 className="text-4xl font-bold mb-4">Planes de visitas médicas para su empresa</h1>
          <p className="text-xl text-amber-100 max-w-2xl mx-auto">
            Compre una bolsa de visitas para todo su equipo en el país: agenda, aprobación del supervisor, check-in y
            check-out con evidencia, ruta del día y reporte de visitas.
          </p>
        </div>
      </div>

      <div className="container mx-auto px-4 py-12">
        {/* Selector de país */}
        {!loading && paises.length > 0 && (
          <div className="flex flex-col md:flex-row justify-between items-center mb-8 gap-4">
            <div className="flex gap-2" role="group" aria-label="País">
              {paises.map((pais) => (
                <Button
                  key={pais.codigo}
                  variant={paisSeleccionado === pais.codigo ? 'default' : 'outline'}
                  size="sm"
                  aria-pressed={paisSeleccionado === pais.codigo}
                  onClick={() => setPaisElegido(pais.codigo)}
                  className={paisSeleccionado === pais.codigo ? 'bg-orange-600 hover:bg-orange-700' : ''}
                >
                  {bandera(pais.codigo)} {pais.nombre}
                </Button>
              ))}
            </div>
          </div>
        )}

        {/* Loading */}
        {loading && (
          <div className="flex justify-center py-12">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-orange-600"></div>
          </div>
        )}

        {!loading && errorCarga && <div className="text-center py-12 text-gray-500">{ERROR_CARGA}</div>}

        {/* Grid planes */}
        {!loading && !errorCarga && planesPais.length > 0 && (
          <div className="grid md:grid-cols-3 gap-8 max-w-5xl mx-auto">
            {planesPais.map((plan) => (
              <Card key={plan.config_id} className="relative overflow-hidden border-2 border-gray-200">
                <CardHeader className="bg-gradient-to-r from-amber-500 to-orange-600 text-white p-6">
                  <div className="flex items-center gap-3 mb-2">
                    <Navigation className="h-8 w-8" />
                    <h3 className="text-2xl font-bold">{plan.plan_nombre}</h3>
                  </div>
                  {plan.plan_descripcion && <p className="text-amber-100 text-sm">{plan.plan_descripcion}</p>}
                </CardHeader>

                <CardContent className="p-6">
                  <div className="mb-6 flex items-baseline gap-1">
                    <span className="text-4xl font-bold text-gray-900">{formatearMonto(plan.precio, plan.moneda)}</span>
                    <span className="text-gray-500">/{plan.duracion_dias} días</span>
                  </div>

                  <ul className="space-y-3 mb-6">
                    <li className="flex items-start gap-2 text-sm">
                      <Check className="h-4 w-4 text-orange-500 mt-0.5 shrink-0" />
                      <span className="text-gray-700 font-medium">{plan.visitas} visitas para todo su equipo</span>
                    </li>
                    <li className="flex items-start gap-2 text-sm">
                      <Check className="h-4 w-4 text-orange-500 mt-0.5 shrink-0" />
                      <span className="text-gray-700 font-medium">Vigencia de {plan.duracion_dias} días</span>
                    </li>
                    {FUNCIONES_REALES.map((f) => (
                      <li key={f} className="flex items-start gap-2 text-sm">
                        <Check className="h-4 w-4 text-orange-500 mt-0.5 shrink-0" />
                        <span className="text-gray-700">{f}</span>
                      </li>
                    ))}
                  </ul>

                  <Button className="w-full bg-gray-900 hover:bg-gray-800" size="lg" onClick={() => setPlanCheckout(plan)}>
                    Elegir plan <ArrowRight className="ml-2 h-4 w-4" />
                  </Button>
                </CardContent>
              </Card>
            ))}
          </div>
        )}

        {!loading && !errorCarga && planesPais.length === 0 && (
          <div className="text-center py-12 text-gray-500">
            Por ahora no hay planes de visitas a la venta. Escriba al equipo de EzPayConnect para más información.
          </div>
        )}

        {/* Lo que incluye el módulo (solo lo que existe) */}
        <div className="mt-16 grid md:grid-cols-3 gap-8">
          <div className="text-center p-6">
            <CalendarCheck className="h-12 w-12 text-orange-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Agenda y aprobación</h3>
            <p className="text-gray-600">Sus visitadores proponen las visitas a médicos y su supervisor las aprueba.</p>
          </div>
          <div className="text-center p-6">
            <ClipboardCheck className="h-12 w-12 text-orange-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Check-in y check-out</h3>
            <p className="text-gray-600">Cada visita queda registrada al llegar y al salir, con evidencia.</p>
          </div>
          <div className="text-center p-6">
            <BarChart3 className="h-12 w-12 text-orange-600 mx-auto mb-4" />
            <h3 className="text-lg font-semibold mb-2">Ruta y reporte</h3>
            <p className="text-gray-600">Usted ve la ruta del día de cada visitador y el reporte de las visitas realizadas.</p>
          </div>
        </div>
      </div>

      {/* Checkout Modal */}
      <Dialog open={!!planCheckout} onOpenChange={() => setPlanCheckout(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <MapPin className="h-5 w-5 text-orange-600" />
              Confirmar compra
            </DialogTitle>
          </DialogHeader>
          {planCheckout && (
            <div className="space-y-4">
              <div className="bg-orange-50 p-4 rounded-lg">
                <h3 className="font-bold text-lg">{planCheckout.plan_nombre}</h3>
                {planCheckout.plan_descripcion && <p className="text-sm text-gray-600">{planCheckout.plan_descripcion}</p>}
                <div className="mt-2">
                  <span className="text-2xl font-bold text-orange-700">
                    {formatearMonto(planCheckout.precio, planCheckout.moneda)}
                  </span>
                </div>
              </div>

              <div className="space-y-2">
                <p className="text-sm"><strong>País:</strong> {bandera(planCheckout.pais_codigo)} {planCheckout.pais_nombre}</p>
                <p className="text-sm">
                  <strong>Incluye:</strong> {planCheckout.visitas} visitas para todo su equipo, vigentes {planCheckout.duracion_dias} días
                </p>
                {esProveedor && (
                  <p className="text-sm"><strong>Usuario:</strong> {userProveedor?.email || user?.email}</p>
                )}
              </div>

              <p className="text-sm text-gray-600">
                El pago es por transferencia bancaria: usted sube el comprobante y, cuando EzPayConnect lo aprueba, las
                visitas se acreditan a su empresa. Si su empresa ya tiene un plan vigente en este país, las visitas se
                suman y la vigencia se extiende {planCheckout.duracion_dias} días.
              </p>

              {!esProveedor && (
                <p className="text-sm text-gray-700">
                  Para comprar, ingrese con la cuenta de su empresa proveedora.{' '}
                  <Link to="/proveedor/login" className="font-medium text-orange-700 underline">
                    Ingresar
                  </Link>
                </p>
              )}

              <div className="flex gap-2">
                {esProveedor && (
                  <Button
                    className="flex-1 bg-orange-600 hover:bg-orange-700"
                    onClick={() => {
                      navigate(
                        `/proveedor/checkout?tipo=plan_visitador&referencia_id=${planCheckout.config_id}&descripcion=${encodeURIComponent(planCheckout.plan_nombre)}`
                      );
                      setPlanCheckout(null);
                    }}
                  >
                    Continuar: pago por transferencia
                  </Button>
                )}
                <Button variant="outline" onClick={() => setPlanCheckout(null)}>
                  Cancelar
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
