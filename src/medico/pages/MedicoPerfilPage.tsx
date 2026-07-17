import { useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/hooks/useAuth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarImage, AvatarFallback } from '@/components/ui/avatar'
import { Loader2, Upload, User } from 'lucide-react'
import { toast } from 'sonner'

export default function MedicoPerfilPage() {
  const { user } = useAuth()
  const [fotoUrl, setFotoUrl] = useState<string | null>(null)
  const [subiendo, setSubiendo] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    let active = true
    if (!user?.id) return
    supabase.from('perfiles').select('avatar_url').eq('id', user.id).maybeSingle()
      .then(({ data }) => { if (active && data?.avatar_url) setFotoUrl(data.avatar_url) })
    return () => { active = false }
  }, [user?.id])

  const onFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file || !user?.id) return
    if (!file.type.startsWith('image/')) { toast.error('Elegí una imagen'); return }
    if (file.size > 2 * 1024 * 1024) { toast.error('La imagen no puede superar 2 MB'); return }
    setSubiendo(true)
    try {
      const ext = file.name.split('.').pop() || 'jpg'
      const path = `${user.id}/${Date.now()}.${ext}`
      const { error: upErr } = await supabase.storage.from('fotos-medicos').upload(path, file, { upsert: true })
      if (upErr) { toast.error('Error subiendo la imagen'); return }
      const { data: pub } = supabase.storage.from('fotos-medicos').getPublicUrl(path)
      const url = pub.publicUrl
      const { data, error } = await supabase.rpc('guardar_foto_medico', { p_url: url })
      if (error || (data as any)?.ok === false) { toast.error('No se pudo guardar la foto'); return }
      setFotoUrl(url)
      toast.success('Foto actualizada')
    } finally {
      setSubiendo(false)
    }
  }

  return (
    <div className="max-w-lg mx-auto space-y-6 p-4">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">Mi Perfil</h1>
        <p className="text-slate-500">Tu foto ayuda a que los pacientes te identifiquen al agendar.</p>
      </div>
      <Card>
        <CardHeader><CardTitle className="text-base">Mi foto</CardTitle></CardHeader>
        <CardContent className="flex flex-col items-center gap-4">
          <Avatar className="h-28 w-28">
            {fotoUrl ? <AvatarImage src={fotoUrl} alt="Mi foto" className="object-cover" /> : null}
            <AvatarFallback><User className="h-10 w-10 text-slate-400" /></AvatarFallback>
          </Avatar>
          <Button onClick={() => inputRef.current?.click()} disabled={subiendo}>
            {subiendo ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Upload className="h-4 w-4 mr-2" />}
            {fotoUrl ? 'Cambiar foto' : 'Subir foto'}
          </Button>
          <input ref={inputRef} type="file" accept="image/*" className="hidden" onChange={onFile} disabled={subiendo} />
          <p className="text-xs text-slate-400">JPG o PNG, máximo 2 MB.</p>
        </CardContent>
      </Card>
    </div>
  )
}
