// src/pages/ConfiguracionPage.tsx
// Dia 19: Configuracion Avanzada - Branding, Notificaciones, Integraciones, Sistema
// EzPayConnect

import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAdminAuth } from '@/hooks/admin/useAdminAuth'
import {
  Settings,
  Palette,
  Bell,
  Plug,
  Globe,
  Save,
  RefreshCw,
  CheckCircle,
  AlertCircle,
  Loader2,
  Type,
  Image,
  Mail,
  MessageCircle,
  Smartphone,
  Calendar,
  DollarSign,
  Clock,
  Languages
} from 'lucide-react'

interface ConfigItem {
  id: string
  clave: string
  valor: string
  tipo: string
  categoria: string
  descripcion: string
  editable: boolean
}

interface ConfigState {
  branding: ConfigItem[]
  notificaciones: ConfigItem[]
  integraciones: ConfigItem[]
  sistema: ConfigItem[]
}

export default function ConfiguracionPage() {
  const { perfil } = useAdminAuth()
  const [activeTab, setActiveTab] = useState<'branding' | 'notificaciones' | 'integraciones' | 'sistema'>('branding')
  const [config, setConfig] = useState<ConfigState>({ branding: [], notificaciones: [], integraciones: [], sistema: [] })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    cargarConfiguracion()
  }, [])

  const cargarConfiguracion = async () => {
    setLoading(true)
    try {
      const { data: result, error: fnError } = await supabase.functions.invoke('actualizar-configuracion', {
        method: 'GET'
      })

      if (fnError) throw fnError

      if (result?.success) {
        setConfig({
          branding: result.data.branding || [],
          notificaciones: result.data.notificaciones || [],
          integraciones: result.data.integraciones || [],
          sistema: result.data.sistema || []
        })
      }
    } catch (err: any) {
      setError('Error cargando configuracion: ' + err.message)
    } finally {
      setLoading(false)
    }
  }

  const guardarCambios = async () => {
    setSaving(true)
    setMessage('')
    setError('')

    try {
      const todasLasConfigs = [
        ...config.branding,
        ...config.notificaciones,
        ...config.integraciones,
        ...config.sistema
      ].filter(c => c.editable)

      const { data: result, error: fnError } = await supabase.functions.invoke('actualizar-configuracion', {
        body: { configuraciones: todasLasConfigs.map(c => ({ clave: c.clave, valor: c.valor })) }
      })

      if (fnError) throw fnError

      if (result?.success) {
        setMessage(`✅ ${result.mensaje}`)
        setTimeout(() => setMessage(''), 3000)
      } else {
        setError('Error al guardar')
      }
    } catch (err: any) {
      setError('Error: ' + err.message)
    } finally {
      setSaving(false)
    }
  }

  const actualizarValor = (categoria: keyof ConfigState, clave: string, nuevoValor: string) => {
    setConfig(prev => ({
      ...prev,
      [categoria]: prev[categoria].map(item =>
        item.clave === clave ? { ...item, valor: nuevoValor } : item
      )
    }))
  }

  const renderInput = (item: ConfigItem, categoria: keyof ConfigState) => {
    if (!item.editable) {
      return <span className="text-gray-500 bg-gray-100 px-3 py-2 rounded-lg">{item.valor}</span>
    }

    switch (item.tipo) {
      case 'booleano':
        return (
          <label className="flex items-center gap-3 cursor-pointer">
            <div className={`relative w-12 h-6 rounded-full transition-colors ${item.valor === 'true' ? 'bg-[#1E5C8E]' : 'bg-gray-300'}`}>
              <input
                type="checkbox"
                checked={item.valor === 'true'}
                onChange={(e) => actualizarValor(categoria, item.clave, e.target.checked ? 'true' : 'false')}
                className="sr-only"
              />
              <div className={`absolute top-1 w-4 h-4 rounded-full bg-white transition-transform ${item.valor === 'true' ? 'translate-x-6' : 'translate-x-1'}`} />
            </div>
            <span className="text-sm text-gray-600">{item.valor === 'true' ? 'Activado' : 'Desactivado'}</span>
          </label>
        )

      case 'color':
        return (
          <div className="flex items-center gap-3">
            <input
              type="color"
              value={item.valor}
              onChange={(e) => actualizarValor(categoria, item.clave, e.target.value)}
              className="w-12 h-10 rounded-lg cursor-pointer border border-gray-200"
            />
            <input
              type="text"
              value={item.valor}
              onChange={(e) => actualizarValor(categoria, item.clave, e.target.value)}
              className="flex-1 p-2 border border-gray-200 rounded-lg font-mono text-sm"
            />
          </div>
        )

      default:
        return (
          <input
            type="text"
            value={item.valor}
            onChange={(e) => actualizarValor(categoria, item.clave, e.target.value)}
            className="w-full p-3 border border-gray-200 rounded-lg focus:outline-none focus:border-[#1E5C8E]"
          />
        )
    }
  }

  const getIconoConfig = (clave: string) => {
    if (clave.includes('email')) return <Mail size={18} className="text-[#1E5C8E]" />
    if (clave.includes('whatsapp')) return <MessageCircle size={18} className="text-green-500" />
    if (clave.includes('sms')) return <Smartphone size={18} className="text-blue-500" />
    if (clave.includes('calendar')) return <Calendar size={18} className="text-purple-500" />
    if (clave.includes('moneda')) return <DollarSign size={18} className="text-green-600" />
    if (clave.includes('hora')) return <Clock size={18} className="text-orange-500" />
    if (clave.includes('idioma')) return <Languages size={18} className="text-pink-500" />
    return <Settings size={18} className="text-gray-400" />
  }

  if (loading) return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <Loader2 className="h-8 w-8 animate-spin text-[#1E5C8E]" />
    </div>
  )

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-[#1a2a3a] mb-2 flex items-center gap-3">
          <Settings size={32} className="text-[#1E5C8E]" />
          Configuracion Avanzada
        </h1>
        <p className="text-gray-500">Personaliza el sistema segun tus necesidades</p>
      </div>

      {/* Mensajes */}
      {message && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-4 mb-6 flex items-center gap-3">
          <CheckCircle size={20} className="text-green-500" />
          <span className="text-green-700">{message}</span>
        </div>
      )}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6 flex items-center gap-3">
          <AlertCircle size={20} className="text-red-500" />
          <span className="text-red-700">{error}</span>
        </div>
      )}

      {/* Tabs */}
      <div className="flex gap-2 mb-6 bg-white p-2 rounded-lg shadow-sm">
        {[
          { key: 'branding', label: 'Branding', icon: Palette },
          { key: 'notificaciones', label: 'Notificaciones', icon: Bell },
          { key: 'integraciones', label: 'Integraciones', icon: Plug },
          { key: 'sistema', label: 'Sistema', icon: Globe },
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
          </button>
        ))}
      </div>

      {/* Boton guardar */}
      <div className="flex justify-end mb-6">
        <button
          onClick={guardarCambios}
          disabled={saving}
          className="px-6 py-3 bg-[#1E5C8E] hover:bg-[#3A8ABF] text-white rounded-lg font-semibold flex items-center gap-2 transition-colors disabled:opacity-50"
        >
          {saving ? <Loader2 size={18} className="animate-spin" /> : <Save size={18} />}
          {saving ? 'Guardando...' : 'Guardar Cambios'}
        </button>
      </div>

      {/* === TAB BRANDING === */}
      {activeTab === 'branding' && (
        <div className="bg-white rounded-xl shadow-sm p-6">
          <h2 className="text-xl font-semibold text-[#1a2a3a] mb-6 flex items-center gap-2">
            <Palette size={22} className="text-[#1E5C8E]" />
            Personalizacion de Marca
          </h2>
          <div className="space-y-6">
            {config.branding.map(item => (
              <div key={item.clave} className="grid grid-cols-1 md:grid-cols-3 gap-4 items-center">
                <div className="md:col-span-1">
                  <label className="font-medium text-[#1a2a3a]">
                    {item.clave === 'app_nombre' && <><Type size={16} className="inline mr-2" />Nombre de la App</>}
                    {item.clave === 'app_logo_url' && <><Image size={16} className="inline mr-2" />URL del Logo</>}
                    {item.clave === 'color_primario' && <><Palette size={16} className="inline mr-2" />Color Principal</>}
                    {item.clave === 'color_secundario' && <><Palette size={16} className="inline mr-2" />Color Secundario</>}
                    {item.clave === 'color_fondo' && <><Palette size={16} className="inline mr-2" />Color de Fondo</>}
                  </label>
                  <p className="text-sm text-gray-500 mt-1">{item.descripcion}</p>
                </div>
                <div className="md:col-span-2">
                  {renderInput(item, 'branding')}
                </div>
              </div>
            ))}
          </div>

          {/* Preview de colores */}
          <div className="mt-8 p-6 bg-gray-50 rounded-lg">
            <h3 className="font-semibold mb-4">Vista previa de colores</h3>
            <div className="flex gap-4">
              <div className="text-center">
                <div 
                  className="w-20 h-20 rounded-lg shadow-sm mb-2" 
                  style={{ backgroundColor: config.branding.find(c => c.clave === 'color_primario')?.valor || '#1E5C8E' }}
                />
                <span className="text-xs text-gray-500">Primario</span>
              </div>
              <div className="text-center">
                <div 
                  className="w-20 h-20 rounded-lg shadow-sm mb-2" 
                  style={{ backgroundColor: config.branding.find(c => c.clave === 'color_secundario')?.valor || '#00f2ff' }}
                />
                <span className="text-xs text-gray-500">Secundario</span>
              </div>
              <div className="text-center">
                <div 
                  className="w-20 h-20 rounded-lg shadow-sm mb-2 border" 
                  style={{ backgroundColor: config.branding.find(c => c.clave === 'color_fondo')?.valor || '#0a0e1a' }}
                />
                <span className="text-xs text-gray-500">Fondo</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* === TAB NOTIFICACIONES === */}
      {activeTab === 'notificaciones' && (
        <div className="bg-white rounded-xl shadow-sm p-6">
          <h2 className="text-xl font-semibold text-[#1a2a3a] mb-6 flex items-center gap-2">
            <Bell size={22} className="text-[#1E5C8E]" />
            Configuracion de Notificaciones
          </h2>
          <div className="space-y-6">
            {config.notificaciones.map(item => (
              <div key={item.clave} className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-3">
                  {getIconoConfig(item.clave)}
                  <div>
                    <p className="font-medium text-[#1a2a3a]">
                      {item.clave === 'notif_email_activo' && 'Notificaciones por Email'}
                      {item.clave === 'notif_whatsapp_activo' && 'Notificaciones por WhatsApp'}
                      {item.clave === 'notif_sms_activo' && 'Notificaciones por SMS'}
                      {item.clave === 'notif_recordatorios_activo' && 'Recordatorios Automaticos'}
                    </p>
                    <p className="text-sm text-gray-500">{item.descripcion}</p>
                  </div>
                </div>
                <div>
                  {renderInput(item, 'notificaciones')}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* === TAB INTEGRACIONES === */}
      {activeTab === 'integraciones' && (
        <div className="bg-white rounded-xl shadow-sm p-6">
          <h2 className="text-xl font-semibold text-[#1a2a3a] mb-6 flex items-center gap-2">
            <Plug size={22} className="text-[#1E5C8E]" />
            Integraciones de Terceros
          </h2>
          <div className="space-y-6">
            {config.integraciones.map(item => (
              <div key={item.clave} className="grid grid-cols-1 md:grid-cols-3 gap-4 items-start">
                <div className="md:col-span-1">
                  <label className="font-medium text-[#1a2a3a] flex items-center gap-2">
                    {getIconoConfig(item.clave)}
                    {item.clave === 'integ_whatsapp_api' && 'WhatsApp Business API'}
                    {item.clave === 'integ_email_smtp' && 'Servidor SMTP'}
                    {item.clave === 'integ_google_calendar' && 'Google Calendar'}
                  </label>
                  <p className="text-sm text-gray-500 mt-1">{item.descripcion}</p>
                </div>
                <div className="md:col-span-2">
                  {item.tipo === 'booleano' ? (
                    <div className="flex items-center gap-3">
                      {renderInput(item, 'integraciones')}
                      <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                        item.valor === 'true' ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'
                      }`}>
                        {item.valor === 'true' ? 'Conectado' : 'Desconectado'}
                      </span>
                    </div>
                  ) : (
                    <div>
                      {renderInput(item, 'integraciones')}
                      <p className="text-xs text-gray-400 mt-1">
                        {item.clave === 'integ_whatsapp_api' && 'Ingresa tu API Key de WhatsApp Business'}
                        {item.clave === 'integ_email_smtp' && 'Formato: host|puerto|usuario|password'}
                      </p>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* === TAB SISTEMA === */}
      {activeTab === 'sistema' && (
        <div className="bg-white rounded-xl shadow-sm p-6">
          <h2 className="text-xl font-semibold text-[#1a2a3a] mb-6 flex items-center gap-2">
            <Globe size={22} className="text-[#1E5C8E]" />
            Preferencias del Sistema
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {config.sistema.map(item => (
              <div key={item.clave} className="bg-gray-50 p-4 rounded-lg">
                <label className="font-medium text-[#1a2a3a] flex items-center gap-2 mb-2">
                  {getIconoConfig(item.clave)}
                  {item.clave === 'sistema_zona_horaria' && 'Zona Horaria'}
                  {item.clave === 'sistema_formato_fecha' && 'Formato de Fecha'}
                  {item.clave === 'sistema_idioma' && 'Idioma'}
                  {item.clave === 'sistema_moneda' && 'Moneda'}
                </label>
                <p className="text-sm text-gray-500 mb-3">{item.descripcion}</p>
                {item.clave === 'sistema_idioma' ? (
                  <div className="relative">
                    <select
                      value={item.valor}
                      onChange={(e) => actualizarValor('sistema', item.clave, e.target.value)}
                      className="w-full p-3 border border-gray-200 rounded-lg appearance-none focus:outline-none focus:border-[#1E5C8E] bg-white"
                    >
                      <option value="es">🇪🇸 Español</option>
                      <option value="en">🇺🇸 English</option>
                    </select>
                  </div>
                ) : item.clave === 'sistema_moneda' ? (
                  <div className="relative">
                    <select
                      value={item.valor}
                      onChange={(e) => actualizarValor('sistema', item.clave, e.target.value)}
                      className="w-full p-3 border border-gray-200 rounded-lg appearance-none focus:outline-none focus:border-[#1E5C8E] bg-white"
                    >
                      <option value="GTQ">🇬🇹 Quetzal Guatemalteco (GTQ)</option>
                      <option value="USD">🇺🇸 Dólar Estadounidense (USD)</option>
                      <option value="MXN">🇲🇽 Peso Mexicano (MXN)</option>
                    </select>
                  </div>
                ) : (
                  renderInput(item, 'sistema')
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
