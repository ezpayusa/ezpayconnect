import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { useAdminAuth } from '@/hooks/admin/useAdminAuth';
import { supabase } from '@/lib/supabase';
import { Globe, Plus, ArrowLeft, RefreshCw } from 'lucide-react';

interface Pais {
  id: string;
  codigo: string;
  nombre: string;
  moneda: string;
  activo: boolean;
}

export default function PaisesPage() {
  const navigate = useNavigate();
  const { isAdmin, loading: adminLoading } = useAdminAuth();
  const [paises, setPaises] = useState<Pais[]>([]);
  const [loading, setLoading] = useState(true);
  const [dialogoNuevo, setDialogoNuevo] = useState(false);
  const [nuevoPais, setNuevoPais] = useState({
    codigo: '',
    nombre: '',
    moneda: '',
  });

  const cargarPaises = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from('configuracion_pais')
      .select('*')
      .order('nombre');

    if (error) {
      console.error('Error:', error.message);
      alert('Error al cargar países: ' + error.message);
    } else {
      setPaises(data || []);
    }
    setLoading(false);
  };

  useEffect(() => {
    if (!adminLoading && !isAdmin) {
      navigate('/dashboard');
      return;
    }
    cargarPaises();
  }, [adminLoading, isAdmin, navigate]);

  const handleToggleActivo = async (pais: Pais) => {
    const { error } = await supabase
      .from('configuracion_pais')
      .update({ activo: !pais.activo })
      .eq('id', pais.id);

    if (error) {
      console.error('Error:', error.message);
      alert('Error: ' + error.message);
    } else {
      alert(`${pais.nombre} ${!pais.activo ? 'activado' : 'desactivado'}`);
      cargarPaises();
    }
  };

  const handleCrearPais = async () => {
    if (!nuevoPais.codigo || !nuevoPais.nombre || !nuevoPais.moneda) {
      alert('Todos los campos son obligatorios');
      return;
    }

    // Insertar país
    const { data: paisData, error: paisError } = await supabase
      .from('configuracion_pais')
      .insert({
        codigo: nuevoPais.codigo.toUpperCase(),
        nombre: nuevoPais.nombre,
        moneda: nuevoPais.moneda.toUpperCase(),
        activo: true,
      })
      .select()
      .single();

    if (paisError || !paisData) {
      console.error('Error:', paisError?.message);
      alert('Error al crear país: ' + (paisError?.message || 'Error desconocido'));
      return;
    }

    // Crear configuraciones de planes para el nuevo país
    const { data: planesBase } = await supabase.from('planes_base').select('id, precio_base, moneda').eq('activo', true);

    for (const plan of planesBase || []) {
      let tasaCambio = 1;
      if (nuevoPais.moneda.toUpperCase() === 'GTQ') tasaCambio = 7.75;
      else if (nuevoPais.moneda.toUpperCase() === 'HNL') tasaCambio = 24.8;
      else if (nuevoPais.moneda.toUpperCase() === 'NIO') tasaCambio = 36.5;
      else if (nuevoPais.moneda.toUpperCase() === 'CRC') tasaCambio = 535;
      else if (nuevoPais.moneda.toUpperCase() === 'MXN') tasaCambio = 17;

      const precioLocal = Math.round(plan.precio_base * tasaCambio * 100) / 100;

      await supabase.from('planes_configuracion').insert({
        pais_id: paisData.id,
        plan_base_id: plan.id,
        precio_local: precioLocal,
        precio_anual: Math.round(precioLocal * 12 * 0.8 * 100) / 100,
        comision_aplicada: 0,
        descuento_porcentaje: 20,
        activo: true,
      });
    }

    alert(`País ${nuevoPais.nombre} creado con configuraciones de planes`);
    setDialogoNuevo(false);
    setNuevoPais({ codigo: '', nombre: '', moneda: '' });
    cargarPaises();
  };

  if (adminLoading) return <div className="flex justify-center p-8">Verificando permisos...</div>;
  if (!isAdmin) return null;

  return (
    <div className="container mx-auto px-4 py-6 max-w-7xl">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate('/admin-ezpay')}>
            <ArrowLeft className="h-5 w-5" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold">Gestión de Países</h1>
            <p className="text-sm text-muted-foreground">Configura países, monedas y comisiones</p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={cargarPaises}><RefreshCw className="h-4 w-4 mr-2" /> Recargar</Button>
          <Button onClick={() => setDialogoNuevo(true)} className="bg-[#1E5C8E] hover:bg-[#164a70]"><Plus className="h-4 w-4 mr-2" /> Nuevo País</Button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <Card>
          <CardContent className="pt-4">
            <p className="text-sm text-muted-foreground">Total Países</p>
            <p className="text-2xl font-bold">{paises.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <p className="text-sm text-muted-foreground">Activos</p>
            <p className="text-2xl font-bold">{paises.filter(p => p.activo).length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <p className="text-sm text-muted-foreground">Monedas</p>
            <p className="text-2xl font-bold">{new Set(paises.map(p => p.moneda)).size}</p>
          </CardContent>
        </Card>
      </div>

      {/* Grid de países */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        {paises.map((pais) => (
          <Card key={pais.id} className={pais.activo ? 'border-blue-200 cursor-pointer hover:shadow-md transition-shadow' : 'border-gray-200 opacity-75 cursor-pointer hover:shadow-md transition-shadow'} onClick={() => navigate(`/admin-ezpay/pais/${pais.id}`)}>
            <CardContent className="pt-6">
              <div className="flex justify-between items-start mb-2">
                <div>
                  <h3 className="text-lg font-bold">{pais.codigo}</h3>
                  <p className="text-sm text-muted-foreground">{pais.nombre}</p>
                </div>
                <span className={`px-2 py-1 rounded text-xs font-semibold ${pais.activo ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-700'}`}>
                  {pais.activo ? 'Activo' : 'Inactivo'}
                </span>
              </div>
              <p className="text-sm text-muted-foreground mb-4">Moneda: <span className="font-medium">{pais.moneda}</span></p>

              <div className="flex items-center justify-end pt-4 border-t">
                <div className="flex items-center gap-2">
                  <Switch checked={pais.activo} onCheckedChange={() => handleToggleActivo(pais)} />
                  <span className="text-sm">Activo</span>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Tabla de países */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Lista de Países</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b">
                  <th className="text-left py-3 px-4">País</th>
                  <th className="text-left py-3 px-4">Código</th>
                  <th className="text-left py-3 px-4">Moneda</th>
                  <th className="text-center py-3 px-4">Activo</th>
                </tr>
              </thead>
              <tbody>
                {paises.map((pais) => (
                  <tr key={pais.id} className="border-b hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/admin-ezpay/pais/${pais.id}`)}>
                    <td className="py-3 px-4 font-medium">{pais.nombre}</td>
                    <td className="py-3 px-4">{pais.codigo}</td>
                    <td className="py-3 px-4">{pais.moneda}</td>
                    <td className="py-3 px-4 text-center">
                      <Switch checked={pais.activo} onCheckedChange={() => handleToggleActivo(pais)} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {/* Dialogo Nuevo País */}
      <Dialog open={dialogoNuevo} onOpenChange={setDialogoNuevo}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Globe className="h-5 w-5 text-[#1E5C8E]" />
              Nuevo País
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="codigo">Código ISO (2 letras) *</Label>
              <Input id="codigo" value={nuevoPais.codigo} onChange={(e) => setNuevoPais({...nuevoPais, codigo: e.target.value.toUpperCase()})} placeholder="Ej: CR, PA, NI, MX" maxLength={2} />
            </div>
            <div>
              <Label htmlFor="nombre">Nombre del País *</Label>
              <Input id="nombre" value={nuevoPais.nombre} onChange={(e) => setNuevoPais({...nuevoPais, nombre: e.target.value})} placeholder="Ej: Costa Rica" />
            </div>
            <div>
              <Label htmlFor="moneda">Moneda (código) *</Label>
              <Input id="moneda" value={nuevoPais.moneda} onChange={(e) => setNuevoPais({...nuevoPais, moneda: e.target.value.toUpperCase()})} placeholder="Ej: CRC, PAB, NIO, MXN" />
            </div>
            <div className="bg-blue-50 p-3 rounded-lg text-sm text-blue-700">
              <p><strong>Nota:</strong> Al crear el país, se generarán automáticamente las configuraciones de precios para todos los planes existentes usando tasas de cambio estimadas.</p>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDialogoNuevo(false)}>Cancelar</Button>
              <Button onClick={handleCrearPais} disabled={!nuevoPais.codigo || !nuevoPais.nombre || !nuevoPais.moneda} className="bg-[#1E5C8E] hover:bg-[#164a70]">
                <Plus className="h-4 w-4 mr-2" /> Crear País
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}