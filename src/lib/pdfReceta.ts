import { jsPDF } from 'jspdf'
import autoTable from 'jspdf-autotable'
import type { Receta, RecetaItem, Paciente, Perfil } from '@/types'
import { folioReceta } from '@/lib/folioReceta'
import { parseFechaLocal } from '@/lib/fecha'

// Exportada para el test de H13 (sin «N/A», tabla dentro del margen).
export function generarPDF(
  receta: Receta,
  items: RecetaItem[],
  paciente: Paciente,
  medico: Perfil,
  cedula?: string | null
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
  // H12: el folio oficial (el mismo del detalle y del aviso), no el id de la fila.
  doc.text(`Folio: ${folioReceta(receta, cedula)}`, pageWidth - 20, 55, { align: 'right' })

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
    // H13: un dato que falta va como «-», no «N/A».
    [`Teléfono:`, paciente.telefono || '-'],
    [`Email:`, paciente.email || '-'],
    [`Fecha de Nacimiento:`, paciente.fecha_nacimiento ? parseFechaLocal(paciente.fecha_nacimiento).toLocaleDateString('es-GT') : '-'],
    [`Género:`, paciente.genero ? paciente.genero.charAt(0).toUpperCase() + paciente.genero.slice(1) : '-'],
    [`Alergias conocidas:`, paciente.alergias || 'Ninguna registrada'],
    [`Contacto de emergencia:`, paciente.emergencia_nombre ? `${paciente.emergencia_nombre} (${paciente.emergencia_telefono || 'Sin teléfono'})` : '-']
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
    // H13: anchos fijos que suman exactamente el ancho útil (210 - 15 - 15 = 180 mm). Antes
    // `cellWidth: 'wrap'` + `tableWidth: 'auto'` dejaban que la tabla creciera con el contenido y se
    // saliera del margen, y «Cant.» tenía 10 mm (el texto mide ~7 mm + 4 mm de padding): se cortaba.
    columnStyles: {
      0: { cellWidth: 8, halign: 'center' },
      1: { cellWidth: 34, fontStyle: 'bold' },
      2: { cellWidth: 20, halign: 'center' },
      3: { cellWidth: 20, halign: 'center' },
      4: { cellWidth: 20, halign: 'center' },
      5: { cellWidth: 14, halign: 'center' },
      6: { cellWidth: 36 },
      7: { cellWidth: 28, fontStyle: 'bold' }
    },
    margin: { left: 15, right: 15 },
    styles: {
      overflow: 'linebreak'
    },
    tableWidth: pageWidth - 30
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
  medico: Perfil,
  cedula?: string | null
) {
  const doc = generarPDF(receta, items, paciente, medico, cedula)

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
  medico: Perfil,
  cedula?: string | null
) {
  const doc = generarPDF(receta, items, paciente, medico, cedula)

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
