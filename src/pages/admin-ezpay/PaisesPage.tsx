import { useState } from 'react';
import { usePaises } from '@/hooks/admin/usePaises';
import { PaisesTable } from '@/components/admin-ezpay/paises/PaisesTable';
import { PaisForm } from '@/components/admin-ezpay/paises/PaisForm';
import { Globe } from 'lucide-react';
import { toast } from 'sonner';

export interface PaisConfig {
  id: string;
  codigo: string;
  nombre: string;
  moneda: string;
  comisiones_activas: boolean;
  porcentaje_comision_default: number;
  activo: boolean;
}

export default function PaisesPage() {
  const { paises, loading, saving, updatePais } = usePaises();
  const [selectedPais, setSelectedPais] = useState<PaisConfig | null>(null);
  const [formOpen, setFormOpen] = useState(false);

  const handleEdit = (pais: PaisConfig) => {
    setSelectedPais(pais);
    setFormOpen(true);
  };

  const handleToggleActivo = async (pais: PaisConfig) => {
    const success = await updatePais(pais.id, { activo: !pais.activo });
    if (success) {
      toast.success(`${pais.nombre} ${pais.activo ? 'desactivado' : 'activado'}`);
    } else {
      toast.error('Error al actualizar el país');
    }
  };

  const handleToggleComisiones = async (pais: PaisConfig) => {
    const success = await updatePais(pais.id, { comisiones_activas: !pais.comisiones_activas });
    if (success) {
      toast.success(`Comisiones ${pais.comisiones_activas ? 'desactivadas' : 'activadas'} en ${pais.nombre}`);
    } else {
      toast.error('Error al actualizar comisiones');
    }
  };

  const handleSave = async (id: string, data: Partial<PaisConfig>) => {
    const success = await updatePais(id, data);
    if (success) {
      toast.success('País actualizado correctamente');
      setFormOpen(false);
      setSelectedPais(null);
    } else {
      toast.error('Error al guardar los cambios');
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[#87CEEB]"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[#1E5C8E] flex items-center gap-2">
            <Globe size={28} />
            Gestión de Países
          </h1>
          <p className="text-gray-500 mt-1">Configura países, monedas y comisiones</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {paises.map((pais) => (
          <div 
            key={pais.id}
            className={`p-4 rounded-xl border-2 transition-all cursor-pointer ${
              pais.activo 
                ? 'border-[#87CEEB] bg-[#87CEEB]/5' 
                : 'border-gray-200 bg-gray-50'
            }`}
            onClick={() => handleEdit(pais)}
          >
            <div className="flex items-center justify-between mb-2">
              <span className="text-3xl">
                {pais.codigo === 'GT' ? '🇬🇹' : pais.codigo === 'SV' ? '🇸🇻' : '🇭🇳'}
              </span>
              <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                pais.activo ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-200 text-gray-500'
              }`}>
                {pais.activo ? 'Activo' : 'Inactivo'}
              </span>
            </div>
            <h3 className="font-semibold text-gray-800">{pais.nombre}</h3>
            <p className="text-sm text-gray-500">Moneda: {pais.moneda}</p>
            <div className="mt-2 flex items-center gap-2">
              <span className={`text-sm font-medium ${pais.comisiones_activas ? 'text-emerald-600' : 'text-gray-400'}`}>
                {pais.comisiones_activas ? `Comisión: ${pais.porcentaje_comision_default}%` : 'Sin comisiones'}
              </span>
            </div>
          </div>
        ))}
      </div>

      <PaisesTable
        paises={paises}
        onEdit={handleEdit}
        onToggleActivo={handleToggleActivo}
        onToggleComisiones={handleToggleComisiones}
      />

      <PaisForm
        pais={selectedPais}
        open={formOpen}
        onClose={() => {
          setFormOpen(false);
          setSelectedPais(null);
        }}
        onSave={handleSave}
        saving={saving}
      />
    </div>
  );
}
