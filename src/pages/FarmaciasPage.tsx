// src/pages/FarmaciasPage.tsx
// Dia 18: Farmacias V2 - Formularios controlados + selector de horario
// EzPayConnect

import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/hooks/useAuth'
import {
  Plus,
  Search,
  Edit2,
  Trash2,
  Package,
  AlertTriangle,
  CheckCircle,
  X,
  Loader2,
  Pill,
  Clock,
  ChevronDown
} from 'lucide-react'

interface Farmacia {
  id: number
  nombre: string
  direccion: string
  telefono: string
  email: string
  encargado: string
  horario: string
  activo: boolean
}

interface Medicamento {
  id: string
  farmacia_id: number
  nombre_medicamento: string
  descripcion: string
  presentacion: string
  stock_actual: number
  stock_minimo: number
  precio_unitario: number
  laboratorio: string
  estado_stock?: string
}

const DIAS_SEMANA = ['Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes', 'Sabado', 'Domingo']
const HORAS = Array.from({ length: 24 }, (_, i) => `${String(i).padStart(2, '0')}:00`)

export default function FarmaciasPage() {
  const { user } = useAuth()
  const [activeTab, setActiveTab] = useState<'farmacias' | 'inventario' | 'alertas'>('farmacias')
  const [farmacias, setFarmacias] = useState<Farmacia[]>([])
  const [medicamentos, setMedicamentos] = useState<Medicamento[]>([])
  const [alertas, setAlertas] = useState<Medicamento[]>([])
  const [loading, setLoading] = useState(true)
  const [searchTerm, setSearchTerm] = useState('')

  const [showModal, setShowModal] = useState(false)
  const [modalType, setModalType] = useState<'farmacia' | 'medicamento'>('farmacia')
  const [editingItem, setEditingItem] = useState<any>(null)
  const [saving, setSaving] = useState(false)

  // Formulario farmacia
  const [farmaciaForm, setFarmaciaForm] = useState({
    nombre: '',
    direccion: '',
    telefono: '',
    email: '',
    encargado: '',
    dias: ['Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes'],
    horaInicio: '08:00',
    horaFin: '20:00'
  })

  // Formulario medicamento
  const [medicamentoForm, setMedicamentoForm] = useState({
    farmacia_id: '',
    nombre_medicamento: '',
    descripcion: '',
    presentacion: '',
    stock_actual: 0,
    stock_minimo: 10,
    precio_unitario: 0,
    laboratorio: ''
  })

  const cargarDatos = useCallback(async () => {
    setLoading(true)
    if (activeTab === 'farmacias') {
      const { data } = await supabase.from('farmacias').select('*').order('nombre')
      setFarmacias(data || [])
    } else if (activeTab === 'inventario') {
      const { data } = await supabase
        .from('farmacia_medicamentos')
        .select('*, farmacia:farmacias(nombre)')
        .eq('activo', true)
        .order('nombre_medicamento')
      setMedicamentos(data || [])
    } else if (activeTab === 'alertas') {
      const { data } = await supabase.from('v_medicamentos_bajo_stock').select('*')
      setAlertas(data || [])
    }
    setLoading(false)
  }, [activeTab])

  useEffect(() => { cargarDatos() }, [cargarDatos])

  const guardarFarmacia = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!farmaciaForm.nombre.trim()) {
      alert('El nombre es obligatorio')
      return
    }

    setSaving(true)
    const horarioTexto = `${farmaciaForm.dias.join('-')}: ${farmaciaForm.horaInicio} a ${farmaciaForm.horaFin}`

    const data = {
      nombre: farmaciaForm.nombre,
      direccion: farmaciaForm.direccion,
      telefono: farmaciaForm.telefono,
      email: farmaciaForm.email,
      encargado: farmaciaForm.encargado,
      horario: horarioTexto
    }

    try {
      if (editingItem) {
        const { error } = await supabase.from('farmacias').update(data).eq('id', editingItem.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('farmacias').insert(data)
        if (error) throw error
      }

      setShowModal(false)
      setEditingItem(null)
      resetFarmaciaForm()
      await cargarDatos()
      alert(editingItem ? 'Farmacia actualizada' : 'Farmacia creada exitosamente')
    } catch (err: any) {
      alert('Error: ' + err.message)
    } finally {
      setSaving(false)
    }
  }

  const guardarMedicamento = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!medicamentoForm.nombre_medicamento.trim() || !medicamentoForm.farmacia_id) {
      alert('Nombre y farmacia son obligatorios')
      return
    }

    setSaving(true)
    const data = {
      farmacia_id: parseInt(medicamentoForm.farmacia_id),
      nombre_medicamento: medicamentoForm.nombre_medicamento,
      descripcion: medicamentoForm.descripcion,
      presentacion: medicamentoForm.presentacion,
      stock_actual: medicamentoForm.stock_actual,
      stock_minimo: medicamentoForm.stock_minimo,
      precio_unitario: medicamentoForm.precio_unitario,
      laboratorio: medicamentoForm.laboratorio
    }

    try {
      if (editingItem) {
        const { error } = await supabase.from('farmacia_medicamentos').update(data).eq('id', editingItem.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('farmacia_medicamentos').insert(data)
        if (error) throw error
      }

      setShowModal(false)
      setEditingItem(null)
      resetMedicamentoForm()
      await cargarDatos()
      alert(editingItem ? 'Medicamento actualizado' : 'Medicamento creado exitosamente')
    } catch (err: any) {
      alert('Error: ' + err.message)
    } finally {
      setSaving(false)
    }
  }

  const resetFarmaciaForm = () => {
    setFarmaciaForm({
      nombre: '', direccion: '', telefono: '', email: '', encargado: '',
      dias: ['Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes'],
      horaInicio: '08:00', horaFin: '20:00'
    })
  }

  const resetMedicamentoForm = () => {
    setMedicamentoForm({
      farmacia_id: '', nombre_medicamento: '', descripcion: '', presentacion: '',
      stock_actual: 0, stock_minimo: 10, precio_unitario: 0, laboratorio: ''
    })
  }

  const abrirModalFarmacia = (item?: any) => {
    setModalType('farmacia')
    if (item) {
      setEditingItem(item)
      setFarmaciaForm({
        nombre: item.nombre || '',
        direccion: item.direccion || '',
        telefono: item.telefono || '',
        email: item.email || '',
        encargado: item.encargado || '',
        dias: ['Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes'],
        horaInicio: '08:00',
        horaFin: '20:00'
      })
    } else {
      setEditingItem(null)
      resetFarmaciaForm()
    }
    setShowModal(true)
  }

  const abrirModalMedicamento = (item?: any) => {
    setModalType('medicamento')
    if (item) {
      setEditingItem(item)
      setMedicamentoForm({
        farmacia_id: String(item.farmacia_id),
        nombre_medicamento: item.nombre_medicamento || '',
        descripcion: item.descripcion || '',
        presentacion: item.presentacion || '',
        stock_actual: item.stock_actual || 0,
        stock_minimo: item.stock_minimo || 10,
        precio_unitario: item.precio_unitario || 0,
        laboratorio: item.laboratorio || ''
      })
    } else {
      setEditingItem(null)
      resetMedicamentoForm()
    }
    setShowModal(true)
  }

  const eliminarItem = async (tabla: string, id: string | number) => {
    if (!confirm('¿Estas seguro de eliminar?')) return
    const { error } = await supabase.from(tabla).delete().eq('id', id)
    if (error) alert('Error: ' + error.message)
    else cargarDatos()
  }

  const toggleDia = (dia: string) => {
    setFarmaciaForm(prev => ({
      ...prev,
      dias: prev.dias.includes(dia)
        ? prev.dias.filter(d => d !== dia)
        : [...prev.dias, dia]
    }))
  }

  const filteredFarmacias = farmacias.filter(f => 
    f.nombre.toLowerCase().includes(searchTerm.toLowerCase()) ||
    f.direccion?.toLowerCase().includes(searchTerm.toLowerCase())
  )

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-[#1a2a3a] mb-2 flex items-center gap-3">
          <Pill size={32} className="text-[#1E5C8E]" />
          Farmacias
        </h1>
        <p className="text-gray-500">Gestion de farmacias e inventario de medicamentos</p>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 mb-6 bg-white p-2 rounded-lg shadow-sm">
        {[
          { key: 'farmacias', label: 'Farmacias', icon: Pill },
          { key: 'inventario', label: 'Inventario', icon: Package },
          { key: 'alertas', label: 'Alertas de Stock', icon: AlertTriangle },
        ].map(tab => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key as any)}
            className={`px-5 py-3 rounded-lg font-semibold flex items-center gap-2 transition-all ${
              activeTab === tab.key
                ? 'bg-[#1E5C8E] text-white'
                : 'text-gray-600 hover:bg-gray-100'
            }`}
          >
            <tab.icon size={18} />
            {tab.label}
            {tab.key === 'alertas' && alertas.length > 0 && (
              <span className="bg-red-500 text-white text-xs px-2 py-0.5 rounded-full">{alertas.length}</span>
            )}
          </button>
        ))}
      </div>

      {/* Search + Add */}
      <div className="flex gap-4 mb-6">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={20} />
          <input
            type="text"
            placeholder="Buscar..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-3 bg-white border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
          />
        </div>
        <button
          onClick={() => activeTab === 'farmacias' ? abrirModalFarmacia() : abrirModalMedicamento()}
          className="px-4 py-3 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold flex items-center gap-2 transition-colors"
        >
          <Plus size={20} />
          {activeTab === 'farmacias' ? 'Nueva Farmacia' : 'Nuevo Medicamento'}
        </button>
      </div>

      {/* === TAB FARMACIAS === */}
      {activeTab === 'farmacias' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="bg-gray-50 text-gray-500 text-sm">
                <th className="px-6 py-4 text-left">Nombre</th>
                <th className="px-6 py-4 text-left">Direccion</th>
                <th className="px-6 py-4 text-left">Telefono</th>
                <th className="px-6 py-4 text-left">Horario</th>
                <th className="px-6 py-4 text-center">Acciones</th>
              </tr>
            </thead>
            <tbody>
              {filteredFarmacias.map(f => (
                <tr key={f.id} className="border-t border-gray-100 hover:bg-gray-50">
                  <td className="px-6 py-4 font-medium">{f.nombre}</td>
                  <td className="px-6 py-4 text-gray-500">{f.direccion || '-'}</td>
                  <td className="px-6 py-4">{f.telefono || '-'}</td>
                  <td className="px-6 py-4 text-sm">{f.horario || '-'}</td>
                  <td className="px-6 py-4 text-center">
                    <button onClick={() => abrirModalFarmacia(f)} className="p-2 text-[#1E5C8E] hover:bg-blue-50 rounded-lg mr-2">
                      <Edit2 size={16} />
                    </button>
                    <button onClick={() => eliminarItem('farmacias', f.id)} className="p-2 text-red-500 hover:bg-red-50 rounded-lg">
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* === TAB INVENTARIO === */}
      {activeTab === 'inventario' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="bg-gray-50 text-gray-500 text-sm">
                <th className="px-6 py-4 text-left">Medicamento</th>
                <th className="px-6 py-4 text-left">Farmacia</th>
                <th className="px-6 py-4 text-center">Stock</th>
                <th className="px-6 py-4 text-center">Minimo</th>
                <th className="px-6 py-4 text-left">Precio</th>
                <th className="px-6 py-4 text-center">Acciones</th>
              </tr>
            </thead>
            <tbody>
              {medicamentos.map(m => (
                <tr key={m.id} className="border-t border-gray-100 hover:bg-gray-50">
                  <td className="px-6 py-4">
                    <div className="font-medium">{m.nombre_medicamento}</div>
                    <div className="text-sm text-gray-500">{m.presentacion}</div>
                  </td>
                  <td className="px-6 py-4">{(m as any).farmacia?.nombre || '-'}</td>
                  <td className="px-6 py-4 text-center">
                    <span className={`px-2 py-1 rounded text-sm font-medium ${
                      m.stock_actual <= m.stock_minimo ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'
                    }`}>
                      {m.stock_actual}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-center text-gray-500">{m.stock_minimo}</td>
                  <td className="px-6 py-4">Q{m.precio_unitario?.toFixed(2) || '0.00'}</td>
                  <td className="px-6 py-4 text-center">
                    <button onClick={() => abrirModalMedicamento(m)} className="p-2 text-[#1E5C8E] hover:bg-blue-50 rounded-lg mr-2">
                      <Edit2 size={16} />
                    </button>
                    <button onClick={() => eliminarItem('farmacia_medicamentos', m.id)} className="p-2 text-red-500 hover:bg-red-50 rounded-lg">
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* === TAB ALERTAS === */}
      {activeTab === 'alertas' && (
        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className="p-6 border-b border-gray-100">
            <h2 className="text-lg font-semibold text-red-600 flex items-center gap-2">
              <AlertTriangle size={22} />
              Medicamentos con Bajo Stock o Agotados
            </h2>
          </div>
          <table className="w-full">
            <thead>
              <tr className="bg-gray-50 text-gray-500 text-sm">
                <th className="px-6 py-4 text-left">Medicamento</th>
                <th className="px-6 py-4 text-left">Farmacia</th>
                <th className="px-6 py-4 text-center">Stock Actual</th>
                <th className="px-6 py-4 text-center">Stock Minimo</th>
                <th className="px-6 py-4 text-center">Estado</th>
              </tr>
            </thead>
            <tbody>
              {alertas.map(a => (
                <tr key={a.id} className="border-t border-gray-100 hover:bg-gray-50">
                  <td className="px-6 py-4 font-medium">{a.nombre_medicamento}</td>
                  <td className="px-6 py-4">{a.farmacia_nombre}</td>
                  <td className="px-6 py-4 text-center font-bold text-red-600">{a.stock_actual}</td>
                  <td className="px-6 py-4 text-center">{a.stock_minimo}</td>
                  <td className="px-6 py-4 text-center">
                    <span className={`px-3 py-1 rounded-full text-xs font-bold ${
                      a.estado_stock === 'agotado' ? 'bg-red-500 text-white' : 'bg-yellow-500 text-white'
                    }`}>
                      {a.estado_stock === 'agotado' ? 'AGOTADO' : 'BAJO STOCK'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* === MODAL FARMACIA === */}
      {showModal && modalType === 'farmacia' && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-lg w-full max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b border-gray-100 flex items-center justify-between">
              <h2 className="text-xl font-semibold text-[#1a2a3a]">
                {editingItem ? 'Editar' : 'Nueva'} Farmacia
              </h2>
              <button onClick={() => setShowModal(false)} className="p-2 hover:bg-gray-100 rounded-lg">
                <X size={20} className="text-gray-400" />
              </button>
            </div>

            <form onSubmit={guardarFarmacia} className="p-6 space-y-4">
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Nombre *</label>
                <input
                  value={farmaciaForm.nombre}
                  onChange={e => setFarmaciaForm({...farmaciaForm, nombre: e.target.value})}
                  required
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Direccion</label>
                <input
                  value={farmaciaForm.direccion}
                  onChange={e => setFarmaciaForm({...farmaciaForm, direccion: e.target.value})}
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Telefono</label>
                  <input
                    value={farmaciaForm.telefono}
                    onChange={e => setFarmaciaForm({...farmaciaForm, telefono: e.target.value})}
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Email</label>
                  <input
                    value={farmaciaForm.email}
                    onChange={e => setFarmaciaForm({...farmaciaForm, email: e.target.value})}
                    type="email"
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
              </div>
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Encargado</label>
                <input
                  value={farmaciaForm.encargado}
                  onChange={e => setFarmaciaForm({...farmaciaForm, encargado: e.target.value})}
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>

              {/* Selector de horario */}
              <div>
                <label className="text-sm text-gray-500 mb-2 block flex items-center gap-2">
                  <Clock size={16} />
                  Dias de atencion
                </label>
                <div className="flex flex-wrap gap-2">
                  {DIAS_SEMANA.map(dia => (
                    <button
                      key={dia}
                      type="button"
                      onClick={() => toggleDia(dia)}
                      className={`px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                        farmaciaForm.dias.includes(dia)
                          ? 'bg-[#1E5C8E] text-white'
                          : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                      }`}
                    >
                      {dia}
                    </button>
                  ))}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Hora apertura</label>
                  <div className="relative">
                    <select
                      value={farmaciaForm.horaInicio}
                      onChange={e => setFarmaciaForm({...farmaciaForm, horaInicio: e.target.value})}
                      className="w-full p-3 border border-gray-200 rounded-lg appearance-none focus:outline-none focus:border-[#1E5C8E]"
                    >
                      {HORAS.map(h => <option key={h} value={h}>{h}</option>)}
                    </select>
                    <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" size={16} />
                  </div>
                </div>
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Hora cierre</label>
                  <div className="relative">
                    <select
                      value={farmaciaForm.horaFin}
                      onChange={e => setFarmaciaForm({...farmaciaForm, horaFin: e.target.value})}
                      className="w-full p-3 border border-gray-200 rounded-lg appearance-none focus:outline-none focus:border-[#1E5C8E]"
                    >
                      {HORAS.map(h => <option key={h} value={h}>{h}</option>)}
                    </select>
                    <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" size={16} />
                  </div>
                </div>
              </div>

              <div className="bg-gray-50 p-3 rounded-lg">
                <p className="text-sm text-gray-600">
                  <strong>Horario resultante:</strong><br/>
                  {farmaciaForm.dias.join('-')}: {farmaciaForm.horaInicio} a {farmaciaForm.horaFin}
                </p>
              </div>

              <div className="flex gap-3 pt-4">
                <button
                  type="submit"
                  disabled={saving}
                  className="flex-1 py-3 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
                >
                  {saving ? <Loader2 size={18} className="animate-spin" /> : <CheckCircle size={18} />}
                  {saving ? 'Guardando...' : (editingItem ? 'Guardar cambios' : 'Crear Farmacia')}
                </button>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="px-6 py-3 bg-gray-100 hover:bg-gray-200 rounded-lg font-semibold transition-colors"
                >
                  Cancelar
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* === MODAL MEDICAMENTO === */}
      {showModal && modalType === 'medicamento' && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl max-w-lg w-full max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b border-gray-100 flex items-center justify-between">
              <h2 className="text-xl font-semibold text-[#1a2a3a]">
                {editingItem ? 'Editar' : 'Nuevo'} Medicamento
              </h2>
              <button onClick={() => setShowModal(false)} className="p-2 hover:bg-gray-100 rounded-lg">
                <X size={20} className="text-gray-400" />
              </button>
            </div>

            <form onSubmit={guardarMedicamento} className="p-6 space-y-4">
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Farmacia *</label>
                <div className="relative">
                  <select
                    value={medicamentoForm.farmacia_id}
                    onChange={e => setMedicamentoForm({...medicamentoForm, farmacia_id: e.target.value})}
                    required
                    className="w-full p-3 border border-gray-200 rounded-lg appearance-none focus:outline-none focus:border-[#1E5C8E]"
                  >
                    <option value="">Seleccionar farmacia</option>
                    {farmacias.map(f => <option key={f.id} value={f.id}>{f.nombre}</option>)}
                  </select>
                  <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none" size={16} />
                </div>
              </div>
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Nombre del medicamento *</label>
                <input
                  value={medicamentoForm.nombre_medicamento}
                  onChange={e => setMedicamentoForm({...medicamentoForm, nombre_medicamento: e.target.value})}
                  required
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Descripcion</label>
                <input
                  value={medicamentoForm.descripcion}
                  onChange={e => setMedicamentoForm({...medicamentoForm, descripcion: e.target.value})}
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>
              <div>
                <label className="text-sm text-gray-500 mb-1 block">Presentacion</label>
                <input
                  value={medicamentoForm.presentacion}
                  onChange={e => setMedicamentoForm({...medicamentoForm, presentacion: e.target.value})}
                  placeholder="Tableta 500mg"
                  className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Stock actual *</label>
                  <input
                    type="number"
                    min="0"
                    value={medicamentoForm.stock_actual}
                    onChange={e => setMedicamentoForm({...medicamentoForm, stock_actual: parseInt(e.target.value) || 0})}
                    required
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Stock minimo *</label>
                  <input
                    type="number"
                    min="1"
                    value={medicamentoForm.stock_minimo}
                    onChange={e => setMedicamentoForm({...medicamentoForm, stock_minimo: parseInt(e.target.value) || 10})}
                    required
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Precio unitario (Q)</label>
                  <input
                    type="number"
                    step="0.01"
                    min="0"
                    value={medicamentoForm.precio_unitario}
                    onChange={e => setMedicamentoForm({...medicamentoForm, precio_unitario: parseFloat(e.target.value) || 0})}
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
                <div>
                  <label className="text-sm text-gray-500 mb-1 block">Laboratorio</label>
                  <input
                    value={medicamentoForm.laboratorio}
                    onChange={e => setMedicamentoForm({...medicamentoForm, laboratorio: e.target.value})}
                    className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
                  />
                </div>
              </div>

              <div className="flex gap-3 pt-4">
                <button
                  type="submit"
                  disabled={saving}
                  className="flex-1 py-3 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
                >
                  {saving ? <Loader2 size={18} className="animate-spin" /> : <CheckCircle size={18} />}
                  {saving ? 'Guardando...' : (editingItem ? 'Guardar cambios' : 'Crear Medicamento')}
                </button>
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="px-6 py-3 bg-gray-100 hover:bg-gray-200 rounded-lg font-semibold transition-colors"
                >
                  Cancelar
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
