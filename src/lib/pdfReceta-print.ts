import { jsPDF } from 'jspdf'
import 'jspdf-autotable'
import type { Receta, RecetaItem, Paciente, Perfil } from '@/types'

function generarPDF(
  receta: Receta,
  items: RecetaItem[],
  paciente: Paciente,
  medico: Perfil
) {
  const doc = new jsPDF()
  const pageWidth = doc.internal.pageSize.getWidth()

  // Colores corporativos EzPayConnect
  const colorSecundario = '#1a2a3a'
  const colorTexto = '#333333'
  const colorGris = '#8a9aaa'

  // === MEMBRETE SUPERIOR ===
  doc.setFillColor(26, 42, 58)
  doc.rect(0, 0, pageWidth, 45, 'F')

  doc.setTextColor(255, 255, 255)
  doc.setFontSize(22)
  doc.setFont('helvetica', 'bold')
  doc.text('EzPayConnect', 20, 22)

  doc.setFontSize(10)
  doc.setFont('helvetica', 'normal')
  doc.text('Software Médico Profesional', 20, 30)
  doc.text('Receta Médica Digital', 20, 36)

  // Info médico (derecha)
  doc.setFontSize(11)
  doc.setFont('helvetica', 'bold')
  doc.text(`Dr. ${medico.nombre_completo || 'Médico'}`, pageWidth - 20, 22, { align: 'right' })
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(9)
  doc.text(medico.email || '', pageWidth - 20, 28, { align: 'right' })
  doc.text(medico.telefono || '', pageWidth - 20, 34, { align: 'right' })

  // === FECHA Y FOLIO ===
  doc.setTextColor(colorGris)
  doc.setFontSize(9)
  const fecha = new Date(receta.created_at).toLocaleDateString('es-GT', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  })
  doc.text(`Fecha de emisión: ${fecha}`, 20, 55)
  doc.text(`Folio: REC-${String(receta.id).padStart(6, '0')}`, pageWidth - 20, 55, { align: 'right' })

  // === DATOS DEL PACIENTE ===
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
    [`Teléfono:`, paciente.telefono || 'N/A'],
    [`Email:`, paciente.email || 'N/A'],
    [`Fecha de Nacimiento:`, paciente.fecha_nacimiento ? new Date(paciente.fecha_nacimiento).toLocaleDateString('es-GT') : 'N/A'],
    [`Género:`, paciente.genero ? paciente.genero.charAt(0).toUpperCase() + paciente.genero.slice(1) : 'N/A'],
    [`Alergias conocidas:`, paciente.alergias || 'Ninguna registrada'],
    [`Contacto de emergencia:`, paciente.emergencia_nombre ? `${paciente.emergencia_nombre} (${paciente.emergencia_telefono || 'Sin teléfono'})` : 'N/A']
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

  // === MEDICAMENTOS PRESCRITOS ===
  yPos += 8
  doc.setFontSize(14)
  doc.setFont('helvetica', 'bold')
  doc.setTextColor(colorSecundario)
  doc.text('Medicamentos Prescritos', 20, yPos)
  doc.line(20, yPos + 3, pageWidth - 20, yPos + 3)

  const tableData = items.map((item, idx) => [
    String(idx + 1),
    item.nombre_medicamento,
    item.dosis,
    item.frecuencia,
    item.duracion || 'Según indicación médica',
    String(item.cantidad),
    item.instrucciones || 'Tomar según prescripción'
  ])

  // Usar autoTable con el plugin importado
  const autoTable = (doc as any).autoTable
  if (typeof autoTable === 'function') {
    autoTable({
      startY: yPos + 8,
      head: [['#', 'Medicamento', 'Dosis', 'Frecuencia', 'Duración', 'Cant.', 'Instrucciones']],
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
  } else {
    // Fallback si autoTable no está disponible
    yPos += 15
    items.forEach((item, idx) => {
      doc.setFontSize(10)
      doc.setFont('helvetica', 'bold')
      doc.text(`${idx + 1}. ${item.nombre_medicamento}`, 20, yPos)
      yPos += 7
      doc.setFont('helvetica', 'normal')
      doc.text(`   Dosis: ${item.dosis} | Frecuencia: ${item.frecuencia} | Duración: ${item.duracion || 'N/A'} | Cantidad: ${item.cantidad}`, 20, yPos)
      yPos += 7
      if (item.instrucciones) {
        doc.text(`   Instrucciones: ${item.instrucciones}`, 20, yPos)
        yPos += 7
      }
      yPos += 5
    })
  }

  // === INSTRUCCIONES GENERALES ===
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

  // === FIRMA DIGITAL ===
  const firmaY = Math.max(finalY + (receta.instrucciones_generales ? 50 : 30), 230)

  doc.setDrawColor(30, 92, 142)
  doc.setLineWidth(0.5)
  doc.line(pageWidth / 2 - 50, firmaY, pageWidth / 2 + 50, firmaY)

  doc.setFontSize(11)
  doc.setFont('helvetica', 'bold')
  doc.setTextColor(colorSecundario)
  doc.text(`Dr. ${medico.nombre_completo || 'Médico'}`, pageWidth / 2, firmaY + 10, { align: 'center' })

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(9)
  doc.setTextColor(colorGris)
  doc.text('Firma y Sello Médico', pageWidth / 2, firmaY + 16, { align: 'center' })
  doc.text('Documento generado digitalmente por EzPayConnect', pageWidth / 2, firmaY + 22, { align: 'center' })

  // === FOOTER ===
  doc.setFillColor(26, 42, 58)
  doc.rect(0, 285, pageWidth, 12, 'F')
  doc.setTextColor(255, 255, 255)
  doc.setFontSize(8)
  doc.text(
    'EzPayConnect - Software Médico | Este documento tiene validez médica digital | No es transferible',
    pageWidth / 2, 292, { align: 'center' }
  )

  return doc
}

export function generarPDFReceta(
  receta: Receta,
  items: RecetaItem[],
  paciente: Paciente,
  medico: Perfil
) {
  const doc = generarPDF(receta, items, paciente, medico)

  // === GUARDAR ARCHIVO ===
  const nombreArchivo = `Receta_${paciente.nombre}_${paciente.apellido}_${new Date().toISOString().split('T')[0]}.pdf`
    .replace(/\s+/g, '_')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')

  doc.save(nombreArchivo)

  return doc
}

// ✅ NUEVO: Función para imprimir directamente
export function imprimirPDFReceta(
  receta: Receta,
  items: RecetaItem[],
  paciente: Paciente,
  medico: Perfil
) {
  const doc = generarPDF(receta, items, paciente, medico)

  // Obtener el PDF como blob
  const pdfBlob = doc.output('blob')
  const pdfUrl = URL.createObjectURL(pdfBlob)

  // Abrir en nueva pestaña para imprimir
  const printWindow = window.open(pdfUrl, '_blank')

  if (printWindow) {
    // Esperar a que cargue y luego imprimir
    printWindow.onload = () => {
      printWindow.focus()
      printWindow.print()
    }
  } else {
    // Si el popup está bloqueado, descargar como fallback
    const nombreArchivo = `Receta_${paciente.nombre}_${paciente.apellido}_${new Date().toISOString().split('T')[0]}.pdf`
      .replace(/\s+/g, '_')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
    doc.save(nombreArchivo)
  }

  // Limpiar URL después de un tiempo
  setTimeout(() => URL.revokeObjectURL(pdfUrl), 60000)

  return doc
}
