// supabase/functions/generar-pdf-receta/index.ts
// Edge Function segura para generar PDFs de recetas medicas

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { jsPDF } from 'https://esm.sh/jspdf@2.5.1'
import 'https://esm.sh/jspdf-autotable@3.8.2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'No autorizado - Se requiere token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') || '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    )

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Token invalido o expirado' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { recetaId } = await req.json()

    if (!recetaId) {
      return new Response(
        JSON.stringify({ error: 'recetaId es requerido' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: receta, error: recetaError } = await supabaseAdmin
      .from('recetas')
      .select(`*, pacientes(*)`)
      .eq('id', recetaId)
      .eq('medico_id', user.id)
      .single()

    if (recetaError || !receta) {
      return new Response(
        JSON.stringify({ error: 'Receta no encontrada o no tienes permiso' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: items, error: itemsError } = await supabaseAdmin
      .from('receta_items')
      .select('*')
      .eq('receta_id', recetaId)

    if (itemsError) {
      return new Response(
        JSON.stringify({ error: 'Error al obtener medicamentos' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: medico, error: medicoError } = await supabaseAdmin
      .from('perfiles')
      .select('*')
      .eq('id', user.id)
      .single()

    const doc = new jsPDF()
    const pageWidth = doc.internal.pageSize.getWidth()
    const paciente = receta.pacientes

    const colorSecundario = '#1a2a3a'
    const colorTexto = '#333333'
    const colorGris = '#8a9aaa'

    doc.setFillColor(26, 42, 58)
    doc.rect(0, 0, pageWidth, 45, 'F')

    doc.setTextColor(255, 255, 255)
    doc.setFontSize(22)
    doc.setFont('helvetica', 'bold')
    doc.text('EzPayConnect', 20, 22)

    doc.setFontSize(10)
    doc.setFont('helvetica', 'normal')
    doc.text('Software Medico Profesional', 20, 30)
    doc.text('Receta Medica Digital', 20, 36)

    doc.setFontSize(11)
    doc.setFont('helvetica', 'bold')
    doc.text(`Dr. ${medico?.nombre_completo || 'Medico'}`, pageWidth - 20, 22, { align: 'right' })
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(9)
    doc.text(medico?.email || '', pageWidth - 20, 28, { align: 'right' })
    doc.text(medico?.telefono || '', pageWidth - 20, 34, { align: 'right' })

    doc.setTextColor(colorGris)
    doc.setFontSize(9)
    const fecha = new Date(receta.created_at).toLocaleDateString('es-GT', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
    })
    doc.text(`Fecha de emision: ${fecha}`, 20, 55)
    doc.text(`Folio: REC-${String(receta.id).padStart(6, '0')}`, pageWidth - 20, 55, { align: 'right' })

    doc.setTextColor(colorSecundario)
    doc.setFontSize(14)
    doc.setFont('helvetica', 'bold')
    doc.text('Datos del Paciente', 20, 70)
    doc.setDrawColor(30, 92, 142)
    doc.setLineWidth(0.5)
    doc.line(20, 73, pageWidth - 20, 73)

    doc.setFontSize(10)
    doc.setFont('helvetica', 'normal')
    doc.setTextColor(colorTexto)

    const pacienteInfo = [
      [`Nombre completo:`, `${paciente.nombre} ${paciente.apellido}`],
      [`Telefono:`, paciente.telefono || 'N/A'],
      [`Email:`, paciente.email || 'N/A'],
      [`Fecha de Nacimiento:`, paciente.fecha_nacimiento ? new Date(paciente.fecha_nacimiento).toLocaleDateString('es-GT') : 'N/A'],
      [`Genero:`, paciente.genero ? paciente.genero.charAt(0).toUpperCase() + paciente.genero.slice(1) : 'N/A'],
      [`Alergias conocidas:`, paciente.alergias || 'Ninguna registrada'],
      [`Contacto de emergencia:`, paciente.emergencia_nombre ? `${paciente.emergencia_nombre} (${paciente.emergencia_telefono || 'Sin telefono'})` : 'N/A']
    ]

    let yPos = 82
    pacienteInfo.forEach(([label, value]) => {
      doc.setFont('helvetica', 'bold')
      doc.text(label, 20, yPos)
      const labelWidth = doc.getTextWidth(label)
      doc.setFont('helvetica', 'normal')
      doc.text(` ${value}`, 20 + labelWidth, yPos)
      yPos += 7
    })

    yPos += 8
    doc.setFontSize(14)
    doc.setFont('helvetica', 'bold')
    doc.setTextColor(colorSecundario)
    doc.text('Medicamentos Prescritos', 20, yPos)
    doc.line(20, yPos + 3, pageWidth - 20, yPos + 3)

    const tableData = (items || []).map((item, idx) => [
      String(idx + 1),
      item.nombre_medicamento,
      item.dosis,
      item.frecuencia,
      item.duracion || 'Segun indicacion medica',
      String(item.cantidad),
      item.instrucciones || 'Tomar segun prescripcion'
    ])

    ;(doc as any).autoTable({
      startY: yPos + 8,
      head: [['#', 'Medicamento', 'Dosis', 'Frecuencia', 'Duracion', 'Cant.', 'Instrucciones']],
      body: tableData,
      theme: 'striped',
      headStyles: {
        fillColor: [30, 92, 142],
        textColor: 255,
        fontSize: 9,
        fontStyle: 'bold',
        halign: 'center'
      },
      bodyStyles: {
        fontSize: 9,
        textColor: 51,
        cellPadding: 3
      },
      alternateRowStyles: {
        fillColor: [232, 240, 248]
      },
      columnStyles: {
        0: { cellWidth: 12, halign: 'center' },
        1: { cellWidth: 'auto', fontStyle: 'bold' },
        2: { cellWidth: 28, halign: 'center' },
        3: { cellWidth: 32, halign: 'center' },
        4: { cellWidth: 35, halign: 'center' },
        5: { cellWidth: 15, halign: 'center' },
        6: { cellWidth: 'auto' }
      },
      margin: { left: 20, right: 20 },
      styles: {
        overflow: 'linebreak',
        cellWidth: 'wrap'
      }
    })

    const finalY = (doc as any).lastAutoTable?.finalY || yPos + 60

    if (receta.instrucciones_generales) {
      yPos = finalY + 15
      doc.setFontSize(12)
      doc.setFont('helvetica', 'bold')
      doc.setTextColor(colorSecundario)
      doc.text('Instrucciones Generales', 20, yPos)
      doc.line(20, yPos + 3, pageWidth - 20, yPos + 3)

      doc.setFontSize(10)
      doc.setFont('helvetica', 'normal')
      doc.setTextColor(colorTexto)
      const splitText = doc.splitTextToSize(receta.instrucciones_generales, pageWidth - 40)
      doc.text(splitText, 20, yPos + 12)
    }

    const firmaY = Math.max(finalY + (receta.instrucciones_generales ? 50 : 30), 230)
    doc.setDrawColor(30, 92, 142)
    doc.setLineWidth(0.5)
    doc.line(pageWidth / 2 - 50, firmaY, pageWidth / 2 + 50, firmaY)

    doc.setFontSize(11)
    doc.setFont('helvetica', 'bold')
    doc.setTextColor(colorSecundario)
    doc.text(`Dr. ${medico?.nombre_completo || 'Medico'}`, pageWidth / 2, firmaY + 10, { align: 'center' })
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(9)
    doc.setTextColor(colorGris)
    doc.text('Firma y Sello Medico', pageWidth / 2, firmaY + 16, { align: 'center' })
    doc.text('Documento generado digitalmente por EzPayConnect', pageWidth / 2, firmaY + 22, { align: 'center' })

    doc.setFillColor(26, 42, 58)
    doc.rect(0, 285, pageWidth, 12, 'F')
    doc.setTextColor(255, 255, 255)
    doc.setFontSize(8)
    doc.text(
      'EzPayConnect - Software Medico | Este documento tiene validez medica digital | No es transferible',
      pageWidth / 2, 292, { align: 'center' }
    )

    const pdfBase64 = doc.output('datauristring').split(',')[1]
    const nombreArchivo = `Receta_${paciente.nombre}_${paciente.apellido}_${new Date().toISOString().split('T')[0]}.pdf`
      .replace(/\s+/g, '_')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')

    return new Response(
      JSON.stringify({
        success: true,
        pdfBase64,
        nombreArchivo,
        folio: `REC-${String(receta.id).padStart(6, '0')}`
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: 'Error interno del servidor', details: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
