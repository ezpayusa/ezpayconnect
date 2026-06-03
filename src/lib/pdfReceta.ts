import { jsPDF } from 'jspdf'
import autoTable from 'jspdf-autotable'
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

  // Logo/Nombre
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

  const tableData = items.map((item, idx) => {
    const farmacia = item.farmacia
    let farmaciaTexto = 'Sin farmacia asignada'
    if (farmacia?.nombre) {
      farmaciaTexto = farmacia.nombre
      if (farmacia.direccion) farmaciaTexto += '\nDir: ' + farmacia.direccion
      if (farmacia.telefono) farmaciaTexto += '\nTel: ' + farmacia.telefono
    } else if (item.farmacia_id) {
      farmaciaTexto = 'Farmacia #' + item.farmacia_id
    }
    // Mostrar precio si existe
    if (item.precio_unitario) {
      const total = item.cantidad * item.precio_unitario
      farmaciaTexto += `\nPrecio: Q${item.precio_unitario.toFixed(2)}`
      if (item.cantidad > 1) {
        farmaciaTexto += ` (Total: Q${total.toFixed(2)})`
      }
    }
    return [
      String(idx + 1),
      item.nombre_medicamento,
      item.dosis,
      item.frecuencia,
      item.duracion || 'Según indicación médica',
      String(item.cantidad),
      item.instrucciones || 'Tomar según prescripción',
      farmaciaTexto
    ]
  })

  // Generar tabla con autoTable
  autoTable(doc, {
    startY: yPos + 8,
    head: [['#', 'Medicamento', 'Dosis', 'Frec.', 'Duración', 'Cant.', 'Instrucciones', 'Farmacia']],
    body: tableData,
    theme: 'striped',
    headStyles: {
      fillColor: [30, 92, 142],
      textColor: 255,
      fontSize: 8,
      fontStyle: 'bold',
      halign: 'center',
      valign: 'middle'
    },
    bodyStyles: {
      fontSize: 8,
      textColor: 51,
      cellPadding: 2,
      valign: 'middle'
    },
    alternateRowStyles: {
      fillColor: [232, 240, 248]
    },
    columnStyles: {
      0: { cellWidth: 8, halign: 'center' },
      1: { cellWidth: 32, fontStyle: 'bold' },
      2: { cellWidth: 18, halign: 'center' },
      3: { cellWidth: 18, halign: 'center' },
      4: { cellWidth: 20, halign: 'center' },
      5: { cellWidth: 10, halign: 'center' },
      6: { cellWidth: 32 },
      7: { cellWidth: 28, fontStyle: 'bold' }
    },
    margin: { left: 15, right: 15 },
    styles: {
      overflow: 'linebreak',
      cellWidth: 'wrap'
    },
    tableWidth: 'auto'
  })

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

// ✅ DESCARGAR PDF - Guarda en la PC
export function generarPDFReceta(
  receta: Receta,
  items: RecetaItem[],
  paciente: Paciente,
  medico: Perfil
) {
  const doc = generarPDF(receta, items, paciente, medico)

  const nombreArchivo = `Receta_${paciente.nombre}_${paciente.apellido}_${new Date().toISOString().split('T')[0]}.pdf`
    .replace(/\s+/g, '_')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')

  doc.save(nombreArchivo)
  return doc
}

// ✅ IMPRIMIR - Abre diálogo de impresión directamente sin descargar
export function imprimirPDFReceta(
  receta: Receta,
  items: RecetaItem[],
  paciente: Paciente,
  medico: Perfil
) {
  const doc = generarPDF(receta, items, paciente, medico)

  // Crear iframe invisible y disparar print() automáticamente
  const pdfBlob = doc.output('blob')
  const pdfUrl = URL.createObjectURL(pdfBlob)
  const iframe = document.createElement('iframe')
  iframe.style.position = 'fixed'
  iframe.style.top = '-9999px'
  iframe.style.left = '-9999px'
  iframe.style.width = '1px'
  iframe.style.height = '1px'
  iframe.style.opacity = '0'
  iframe.src = pdfUrl
  document.body.appendChild(iframe)

  // Esperar a que cargue el PDF e imprimir
  const doPrint = () => {
    try {
      iframe.contentWindow?.print()
    } catch (e) {
      console.error('Error imprimiendo:', e)
    }
  }

  iframe.onload = doPrint
  // Fallback por si onload no se dispara en algunos navegadores
  setTimeout(doPrint, 1000)

  // Limpiar después de un tiempo
  setTimeout(() => {
    if (iframe.parentNode) document.body.removeChild(iframe)
    URL.revokeObjectURL(pdfUrl)
  }, 120000)

  return doc
}
