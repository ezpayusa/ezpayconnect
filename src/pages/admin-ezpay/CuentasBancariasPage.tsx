import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { toast } from 'sonner'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Landmark, Loader2, Save, Trash2, Plus } from 'lucide-react'

interface Pais {
  id: string
  nombre: string
  moneda: string | null
}

interface Cuenta {
  id: string
  pais_id: string | null
  banco: string
  tipo_cuenta: string | null
  numero_cuenta: string
  titular: string
  nit: string | null
  moneda: string | null
  instrucciones: string | null
  email_pagos: string | null
  activo: boolean
}

const FORM_VACIO = {
  id: '' as string | '',
  pais_id: '',
  banco: '',
  tipo_cuenta: 'Cuenta Monetaria',
  numero_cuenta: '',
  titular: '',
  nit: '',
  moneda: '',
  instrucciones: '',
  email_pagos: '',
  activo: true,
}

export default function CuentasBancariasPage() {
  const [paises, setPaises] = useState<Pais[]>([])
  const [cuentas, setCuentas] = useState<Cuenta[]>([])
  const [form, setForm] = useState({ ...FORM_VACIO })
  const [loading, setLoading] = useState(true)
  const [guardando, setGuardando] = useState(false)

  const cargar = useCallback(async () => {
    setLoading(true)
    const [{ data: paisesData }, { data: cuentasData }] = await Promise.all([
      supabase.from('configuracion_pais').select('id, nombre, moneda').eq('activo', true).order('nombre'),
      supabase.from('cuentas_bancarias_pais').select('*').order('created_at'),
    ])
    setPaises((paisesData || []) as Pais[])
    setCuentas((cuentasData || []) as Cuenta[])
    setLoading(false)
  }, [])

  useEffect(() => {
    cargar()
  }, [cargar])

  // Al elegir país: si ya tiene cuenta, cargarla para editar; si no, nueva con moneda del país
  const onSelectPais = (paisId: string) => {
    const existente = cuentas.find((c) => c.pais_id === paisId)
    if (existente) {
      setForm({
        id: existente.id,
        pais_id: existente.pais_id || '',
        banco: existente.banco || '',
        tipo_cuenta: existente.tipo_cuenta || 'Cuenta Monetaria',
        numero_cuenta: existente.numero_cuenta || '',
        titular: existente.titular || '',
        nit: existente.nit || '',
        moneda: existente.moneda || '',
        instrucciones: existente.instrucciones || '',
        email_pagos: existente.email_pagos || '',
        activo: existente.activo,
      })
    } else {
      const pais = paises.find((p) => p.id === paisId)
      setForm({ ...FORM_VACIO, pais_id: paisId, moneda: pais?.moneda || '' })
    }
  }

  const guardar = async () => {
    if (!form.pais_id) return toast.error('Selecciona un país')
    if (!form.banco.trim() || !form.numero_cuenta.trim() || !form.titular.trim()) {
      return toast.error('Banco, número de cuenta y titular son obligatorios')
    }
    setGuardando(true)
    const payload = {
      pais_id: form.pais_id,
      banco: form.banco.trim(),
      tipo_cuenta: form.tipo_cuenta || null,
      numero_cuenta: form.numero_cuenta.trim(),
      titular: form.titular.trim(),
      nit: form.nit.trim() || null,
      moneda: form.moneda.trim() || null,
      instrucciones: form.instrucciones.trim() || null,
      email_pagos: form.email_pagos.trim() || null,
      activo: form.activo,
      updated_at: new Date().toISOString(),
    }
    const { error } = form.id
      ? await supabase.from('cuentas_bancarias_pais').update(payload).eq('id', form.id)
      : await supabase.from('cuentas_bancarias_pais').insert(payload)
    setGuardando(false)
    if (error) return toast.error('Error: ' + error.message)
    toast.success('Cuenta bancaria guardada')
    setForm({ ...FORM_VACIO })
    cargar()
  }

  const eliminar = async (id: string) => {
    if (!confirm('¿Eliminar esta cuenta bancaria?')) return
    const { error } = await supabase.from('cuentas_bancarias_pais').delete().eq('id', id)
    if (error) return toast.error('Error: ' + error.message)
    toast.success('Cuenta eliminada')
    if (form.id === id) setForm({ ...FORM_VACIO })
    cargar()
  }

  const nombrePais = (paisId: string | null) => paises.find((p) => p.id === paisId)?.nombre || '—'

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-10 w-10 animate-spin text-[#1E5C8E]" />
      </div>
    )
  }

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1a2a3a] flex items-center gap-2">
          <Landmark className="h-7 w-7 text-[#1E5C8E]" />
          Cuentas Bancarias por País
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Configura la cuenta donde los clientes de cada país depositan/transfieren. Solo los países con cuenta verán la opción de transferencia en el checkout.
        </p>
      </div>

      {/* Formulario */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg flex items-center gap-2">
            {form.id ? <Save className="h-5 w-5 text-[#1E5C8E]" /> : <Plus className="h-5 w-5 text-[#1E5C8E]" />}
            {form.id ? 'Editar cuenta' : 'Nueva cuenta'}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <Label>País *</Label>
              <Select value={form.pais_id} onValueChange={onSelectPais}>
                <SelectTrigger><SelectValue placeholder="Seleccionar país" /></SelectTrigger>
                <SelectContent>
                  {paises.map((p) => (
                    <SelectItem key={p.id} value={p.id}>{p.nombre}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Moneda</Label>
              <Input value={form.moneda} onChange={(e) => setForm({ ...form, moneda: e.target.value })} placeholder="GTQ" />
            </div>
            <div>
              <Label>Banco *</Label>
              <Input value={form.banco} onChange={(e) => setForm({ ...form, banco: e.target.value })} placeholder="Banco Industrial" />
            </div>
            <div>
              <Label>Tipo de cuenta</Label>
              <Select value={form.tipo_cuenta} onValueChange={(v) => setForm({ ...form, tipo_cuenta: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Cuenta Monetaria">Cuenta Monetaria</SelectItem>
                  <SelectItem value="Cuenta de Ahorro">Cuenta de Ahorro</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Número de cuenta *</Label>
              <Input value={form.numero_cuenta} onChange={(e) => setForm({ ...form, numero_cuenta: e.target.value })} placeholder="123-456789-0" />
            </div>
            <div>
              <Label>Titular *</Label>
              <Input value={form.titular} onChange={(e) => setForm({ ...form, titular: e.target.value })} placeholder="EzPayConnect S.A." />
            </div>
            <div>
              <Label>NIT</Label>
              <Input value={form.nit} onChange={(e) => setForm({ ...form, nit: e.target.value })} placeholder="1234567-8" />
            </div>
            <div>
              <Label>Email para comprobantes</Label>
              <Input value={form.email_pagos} onChange={(e) => setForm({ ...form, email_pagos: e.target.value })} placeholder="pagos@ezpayconnect.com" />
            </div>
          </div>
          <div>
            <Label>Instrucciones</Label>
            <Textarea
              value={form.instrucciones}
              onChange={(e) => setForm({ ...form, instrucciones: e.target.value })}
              rows={2}
              placeholder="Ej: Incluye tu nombre/email en el concepto y sube el comprobante."
            />
          </div>
          <div className="flex items-center gap-3">
            <Button className="bg-[#1E5C8E] hover:bg-[#164a70]" onClick={guardar} disabled={guardando}>
              {guardando ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
              {form.id ? 'Actualizar' : 'Guardar'}
            </Button>
            {form.id && (
              <Button variant="outline" onClick={() => setForm({ ...FORM_VACIO })}>Cancelar edición</Button>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Listado */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Cuentas configuradas ({cuentas.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {cuentas.length === 0 ? (
            <p className="text-center text-muted-foreground py-6">Aún no hay cuentas configuradas.</p>
          ) : (
            <div className="space-y-3">
              {cuentas.map((c) => (
                <div key={c.id} className="flex items-start justify-between border rounded-lg p-3">
                  <div className="text-sm">
                    <p className="font-semibold text-[#1a2a3a]">{nombrePais(c.pais_id)} · {c.banco} {!c.activo && <span className="text-red-500">(inactiva)</span>}</p>
                    <p className="text-muted-foreground">{c.tipo_cuenta} · {c.numero_cuenta} · {c.moneda}</p>
                    <p className="text-muted-foreground">{c.titular}{c.nit ? ` · NIT ${c.nit}` : ''}</p>
                  </div>
                  <div className="flex gap-2 shrink-0">
                    <Button variant="outline" size="sm" onClick={() => onSelectPais(c.pais_id || '')}>Editar</Button>
                    <Button variant="ghost" size="sm" className="text-red-600 hover:bg-red-50" onClick={() => eliminar(c.id)}>
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
