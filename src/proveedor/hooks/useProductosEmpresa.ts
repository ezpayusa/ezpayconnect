import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useProveedorAuth } from './useProveedorAuth'
import type { ProductoEmpresa } from '@/proveedor/types/proveedor.types'
import { toast } from 'sonner'

export function useProductosEmpresa() {
  const { empresa, cuenta } = useProveedorAuth()
  const [productos, setProductos] = useState<ProductoEmpresa[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const fetchProductos = useCallback(async () => {
    if (!empresa?.id) return
    setLoading(true)
    const { data, error } = await supabase
      .from('productos_empresa')
      .select('*')
      .eq('empresa_id', empresa.id)
      .order('created_at', { ascending: false })

    if (error) {
      toast.error('Error cargando productos')
      console.error(error)
    } else {
      setProductos(data || [])
    }
    setLoading(false)
  }, [empresa?.id])

  useEffect(() => {
    fetchProductos()
  }, [fetchProductos])

  const crearProducto = async (
    producto: Partial<ProductoEmpresa>,
    imagenFile?: File | null
  ): Promise<boolean> => {
    if (!empresa?.id || !cuenta) {
      toast.error('No hay empresa vinculada')
      return false
    }

    setSaving(true)
    let imagen_url: string | null = producto.imagen_url || null

    if (imagenFile) {
      const fileExt = imagenFile.name.split('.').pop()
      const fileName = `${empresa.id}/${Date.now()}.${fileExt}`
      const { error: uploadError } = await supabase.storage
        .from('productos')
        .upload(fileName, imagenFile, { upsert: true })

      if (uploadError) {
        toast.error('Error subiendo imagen')
        console.error(uploadError)
        setSaving(false)
        return false
      }

      const { data: publicUrlData } = supabase.storage.from('productos').getPublicUrl(fileName)
      imagen_url = publicUrlData.publicUrl
    }

    const { error } = await supabase.from('productos_empresa').insert({
      empresa_id: empresa.id,
      nombre_producto: producto.nombre_producto || '',
      principio_activo: producto.principio_activo || null,
      presentacion: producto.presentacion || null,
      concentracion: producto.concentracion || null,
      categoria: producto.categoria || null,
      precio_unitario: producto.precio_unitario || 0,
      moneda: producto.moneda || 'GTQ',
      stock_disponible: producto.stock_disponible || 0,
      requiere_receta: producto.requiere_receta || false,
      imagen_url,
      estado: 'activo',
    })

    setSaving(false)
    if (error) {
      toast.error('Error creando producto')
      console.error(error)
      return false
    }

    toast.success('Producto creado')
    fetchProductos()
    return true
  }

  // Carga masiva: inserta muchos productos de una sola vez (importación por archivo).
  // No maneja imágenes (se agregan luego por producto). Devuelve cuántos se crearon.
  const crearProductosMasivo = async (
    productos: Partial<ProductoEmpresa>[]
  ): Promise<{ creados: number; error: string | null }> => {
    if (!empresa?.id || !cuenta) {
      return { creados: 0, error: 'No hay empresa vinculada' }
    }
    if (productos.length === 0) {
      return { creados: 0, error: 'No hay productos para importar' }
    }

    setSaving(true)
    const rows = productos.map((p) => ({
      empresa_id: empresa.id,
      nombre_producto: p.nombre_producto || '',
      principio_activo: p.principio_activo || null,
      presentacion: p.presentacion || null,
      concentracion: p.concentracion || null,
      categoria: p.categoria || null,
      precio_unitario: p.precio_unitario || 0,
      moneda: p.moneda || 'GTQ',
      stock_disponible: p.stock_disponible || 0,
      requiere_receta: p.requiere_receta || false,
      estado: 'activo',
    }))

    const { data, error } = await supabase
      .from('productos_empresa')
      .insert(rows)
      .select('id')

    setSaving(false)
    if (error) {
      console.error(error)
      return { creados: 0, error: error.message }
    }

    fetchProductos()
    return { creados: data?.length ?? rows.length, error: null }
  }

  const actualizarProducto = async (
    id: string,
    producto: Partial<ProductoEmpresa>,
    imagenFile?: File | null
  ): Promise<boolean> => {
    if (!empresa?.id) return false

    setSaving(true)
    let imagen_url: string | null | undefined = producto.imagen_url

    if (imagenFile) {
      const fileExt = imagenFile.name.split('.').pop()
      const fileName = `${empresa.id}/${Date.now()}.${fileExt}`
      const { error: uploadError } = await supabase.storage
        .from('productos')
        .upload(fileName, imagenFile, { upsert: true })

      if (uploadError) {
        toast.error('Error subiendo imagen')
        console.error(uploadError)
        setSaving(false)
        return false
      }

      const { data: publicUrlData } = supabase.storage.from('productos').getPublicUrl(fileName)
      imagen_url = publicUrlData.publicUrl
    }

    const updateData: any = {
      nombre_producto: producto.nombre_producto,
      principio_activo: producto.principio_activo,
      presentacion: producto.presentacion,
      concentracion: producto.concentracion,
      categoria: producto.categoria,
      precio_unitario: producto.precio_unitario,
      moneda: producto.moneda,
      stock_disponible: producto.stock_disponible,
      requiere_receta: producto.requiere_receta,
      estado: producto.estado,
    }

    if (imagen_url !== undefined) updateData.imagen_url = imagen_url

    const { error } = await supabase.from('productos_empresa').update(updateData).eq('id', id)

    setSaving(false)
    if (error) {
      toast.error('Error actualizando producto')
      console.error(error)
      return false
    }

    toast.success('Producto actualizado')
    fetchProductos()
    return true
  }

  const eliminarProducto = async (id: string): Promise<boolean> => {
    if (!confirm('¿Eliminar este producto permanentemente?')) return false

    const { error } = await supabase.from('productos_empresa').delete().eq('id', id)
    if (error) {
      toast.error('Error eliminando producto')
      console.error(error)
      return false
    }

    toast.success('Producto eliminado')
    fetchProductos()
    return true
  }

  return {
    productos,
    loading,
    saving,
    fetchProductos,
    crearProducto,
    crearProductosMasivo,
    actualizarProducto,
    eliminarProducto,
  }
}
