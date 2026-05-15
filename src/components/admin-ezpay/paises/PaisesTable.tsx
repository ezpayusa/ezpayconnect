import { Switch } from '@/components/ui/switch';
import { Edit } from 'lucide-react';

export interface PaisConfig {
  id: string;
  codigo: string;
  nombre: string;
  moneda: string;
  comisiones_activas: boolean;
  porcentaje_comision_default: number;
  activo: boolean;
}

interface PaisesTableProps {
  paises: PaisConfig[];
  onEdit: (pais: PaisConfig) => void;
  onToggleActivo: (pais: PaisConfig) => void;
  onToggleComisiones: (pais: PaisConfig) => void;
}

export function PaisesTable({ paises, onEdit, onToggleActivo, onToggleComisiones }: PaisesTableProps) {
  const getBandera = (codigo: string) => {
    const banderas: Record<string, string> = {
      'GT': '🇬🇹',
      'SV': '🇸🇻',
      'HN': '🇭🇳'
    };
    return banderas[codigo] || '🌎';
  };

  return (
    <div className="bg-white rounded-xl shadow-md overflow-hidden">
      <table className="w-full">
        <thead className="bg-[#87CEEB]/10">
          <tr>
            <th className="px-6 py-4 text-left text-sm font-semibold text-[#1E5C8E]">País</th>
            <th className="px-6 py-4 text-left text-sm font-semibold text-[#1E5C8E]">Código</th>
            <th className="px-6 py-4 text-left text-sm font-semibold text-[#1E5C8E]">Moneda</th>
            <th className="px-6 py-4 text-center text-sm font-semibold text-[#1E5C8E]">Comisiones</th>
            <th className="px-6 py-4 text-center text-sm font-semibold text-[#1E5C8E]">% Comisión</th>
            <th className="px-6 py-4 text-center text-sm font-semibold text-[#1E5C8E]">Activo</th>
            <th className="px-6 py-4 text-center text-sm font-semibold text-[#1E5C8E]">Acciones</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {paises.map((pais) => (
            <tr key={pais.id} className="hover:bg-gray-50 transition-colors">
              <td className="px-6 py-4">
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{getBandera(pais.codigo)}</span>
                  <span className="font-medium text-gray-800">{pais.nombre}</span>
                </div>
              </td>
              <td className="px-6 py-4 text-sm text-gray-600 font-mono">{pais.codigo}</td>
              <td className="px-6 py-4 text-sm text-gray-600">{pais.moneda}</td>
              <td className="px-6 py-4 text-center">
                <Switch
                  checked={pais.comisiones_activas}
                  onCheckedChange={() => onToggleComisiones(pais)}
                  className="data-[state=checked]:bg-[#87CEEB]"
                />
              </td>
              <td className="px-6 py-4 text-center">
                <span className={`inline-flex px-3 py-1 rounded-full text-sm font-medium ${
                  pais.comisiones_activas 
                    ? 'bg-emerald-100 text-emerald-700' 
                    : 'bg-gray-100 text-gray-500'
                }`}>
                  {pais.porcentaje_comision_default}%
                </span>
              </td>
              <td className="px-6 py-4 text-center">
                <Switch
                  checked={pais.activo}
                  onCheckedChange={() => onToggleActivo(pais)}
                  className="data-[state=checked]:bg-[#1E5C8E]"
                />
              </td>
              <td className="px-6 py-4 text-center">
                <div className="flex items-center justify-center gap-2">
                  <button
                    onClick={() => onEdit(pais)}
                    className="p-2 text-[#1E5C8E] hover:bg-[#87CEEB]/20 rounded-lg transition-colors"
                    title="Editar país"
                  >
                    <Edit size={18} />
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
