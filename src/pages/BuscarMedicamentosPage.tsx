import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useBusquedaMedicamentos } from '@/hooks/useBusquedaMedicamentos';
import { Search, MapPin, Phone, DollarSign, Package, Building2, ArrowLeft, Copy, CheckCircle, ShoppingCart } from 'lucide-react';
import { toast } from 'sonner';

export default function BuscarMedicamentosPage() {
  const navigate = useNavigate();
  const { resultados, loading, buscar } = useBusquedaMedicamentos();
  const [query, setQuery] = useState('');
  const [seleccionado, setSeleccionado] = useState<string | null>(null);
  const [copiado, setCopiado] = useState(false);

  const handleBuscar = (e: React.FormEvent) => {
    e.preventDefault();
    buscar(query);
  };

  const handleCopiarInfo = (item: any) => {
    const texto = `Medicamento: ${item.nombre_medicamento}\nPresentación: ${item.presentacion}\nFarmacia: ${item.farmacia?.nombre}\nDirección: ${item.farmacia?.direccion}\nTeléfono: ${item.farmacia?.telefono}\nPrecio: Q${item.precio_unitario}\nStock: ${item.stock_actual} unidades`;
    navigator.clipboard.writeText(texto);
    setCopiado(true);
    toast.success('Información copiada al portapapeles');
    setTimeout(() => setCopiado(false), 2000);
  };

  // Agrupar resultados por medicamento
  const agrupados = resultados.reduce((acc: any, item) => {
    const key = item.nombre_medicamento;
    if (!acc[key]) acc[key] = [];
    acc[key].push(item);
    return acc;
  }, {});

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      {/* Header */}
      <div className="flex items-center gap-4 mb-6">
        <Button variant="ghost" size="icon" onClick={() => navigate('/dashboard')}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-2xl font-bold">Buscar Medicamentos</h1>
          <p className="text-sm text-muted-foreground">
            Encuentra el mejor precio y ubicación para tus recetas
          </p>
        </div>
      </div>

      {/* Buscador */}
      <Card className="mb-6">
        <CardContent className="pt-6">
          <form onSubmit={handleBuscar} className="flex gap-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Escribe el nombre del medicamento (ej: Paracetamol, Ibuprofeno...)"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="pl-9"
              />
            </div>
            <Button type="submit" disabled={loading} className="bg-[#1E5C8E] hover:bg-[#164a70]">
              <Search className="h-4 w-4 mr-2" />
              {loading ? 'Buscando...' : 'Buscar'}
            </Button>
          </form>
        </CardContent>
      </Card>

      {/* Resultados */}
      {Object.keys(agrupados).length > 0 && (
        <div className="space-y-6">
          {Object.entries(agrupados).map(([nombreMedicamento, farmacias]: [string, any]) => (
            <Card key={nombreMedicamento} className="overflow-hidden">
              <CardHeader className="bg-gradient-to-r from-[#1E5C8E] to-[#2A7CC4] text-white">
                <div className="flex items-center justify-between">
                  <div>
                    <CardTitle className="text-xl">{nombreMedicamento}</CardTitle>
                    <p className="text-blue-100 text-sm mt-1">
                      {farmacias[0]?.descripcion} • {farmacias[0]?.presentacion} • {farmacias[0]?.laboratorio}
                    </p>
                  </div>
                  <Badge className="bg-white/20 text-white border-0">
                    {farmacias.length} farmacia{farmacias.length > 1 ? 's' : ''} disponible{farmacias.length > 1 ? 's' : ''}
                  </Badge>
                </div>
              </CardHeader>

              <CardContent className="p-0">
                <div className="divide-y">
                  {farmacias.map((item: any) => (
                    <div
                      key={item.id}
                      className={`p-4 flex items-start gap-4 hover:bg-gray-50 transition-colors cursor-pointer ${
                        seleccionado === item.id ? 'bg-blue-50 border-l-4 border-[#1E5C8E]' : ''
                      }`}
                      onClick={() => setSeleccionado(seleccionado === item.id ? null : item.id)}
                    >
                      {/* Icono farmacia */}
                      <div className="mt-1">
                        <Building2 className="h-5 w-5 text-[#1E5C8E]" />
                      </div>

                      {/* Info */}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between mb-1">
                          <h3 className="font-semibold text-gray-900">{item.farmacia?.nombre}</h3>
                          {item.stock_actual <= item.stock_minimo && (
                            <Badge variant="outline" className="text-amber-600 border-amber-600">
                              Stock bajo
                            </Badge>
                          )}
                        </div>

                        <div className="grid grid-cols-1 md:grid-cols-3 gap-2 text-sm text-muted-foreground">
                          <div className="flex items-center gap-1">
                            <MapPin className="h-3.5 w-3.5" />
                            <span className="truncate">{item.farmacia?.direccion}</span>
                          </div>
                          <div className="flex items-center gap-1">
                            <Phone className="h-3.5 w-3.5" />
                            <span>{item.farmacia?.telefono}</span>
                          </div>
                          <div className="flex items-center gap-1">
                            <Package className="h-3.5 w-3.5" />
                            <span>{item.stock_actual} en stock</span>
                          </div>
                        </div>

                        <div className="mt-2 flex items-center justify-between">
                          <div className="flex items-center gap-1 text-lg font-bold text-[#1E5C8E]">
                            <DollarSign className="h-5 w-5" />
                            Q {item.precio_unitario.toFixed(2)}
                          </div>

                          {seleccionado === item.id && (
                            <div className="flex gap-2">
                              <Button
                                variant="outline"
                                size="sm"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleCopiarInfo(item);
                                }}
                              >
                                {copiado ? <CheckCircle className="h-4 w-4 mr-1" /> : <Copy className="h-4 w-4 mr-1" />}
                                {copiado ? 'Copiado' : 'Copiar info'}
                              </Button>
                              <Button
                                size="sm"
                                className="bg-[#1E5C8E] hover:bg-[#164a70]"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  toast.success('Farmacia seleccionada para la receta');
                                  // Aquí se integraría con el sistema de recetas
                                }}
                              >
                                <ShoppingCart className="h-4 w-4 mr-1" />
                                Seleccionar
                              </Button>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Estado vacío */}
      {query && !loading && resultados.length === 0 && (
        <Card className="p-8 text-center">
          <Package className="h-12 w-12 text-gray-300 mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-gray-900 mb-2">No se encontraron resultados</h3>
          <p className="text-muted-foreground">
            No hay farmacias con &quot;{query}&quot; en stock actualmente.
          </p>
        </Card>
      )}

      {/* Instrucciones iniciales */}
      {!query && (
        <Card className="p-8 text-center">
          <Search className="h-12 w-12 text-gray-300 mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-gray-900 mb-2">Busca un medicamento</h3>
          <p className="text-muted-foreground max-w-md mx-auto">
            Escribe el nombre del medicamento arriba para ver qué farmacias lo tienen disponible, 
            comparar precios y seleccionar la mejor opción para tu paciente.
          </p>
        </Card>
      )}
    </div>
  );
}
