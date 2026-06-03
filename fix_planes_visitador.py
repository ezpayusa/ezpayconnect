
import re

filepath = r"C:\Users\Chian\OneDrive\Escritorio\ezpayconnect\src\pages\planes\PlanesVisitadorConfigPage.tsx"

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the problematic DraggableWindow for eliminar config with AlertDialog
old_block = """{/* ════════════════════════════════════════════════════
    VENTANA ARRASTRABLE: Confirmar Eliminar Configuración
    ════════════════════════════════════════════════════ */}
<DraggableWindow
  isOpen={!!dialogoEliminarConfig}
  onClose={() => setDialogoEliminarConfig(null)}
  title="Eliminar Configuración"
  initialPosition={{ x: window.innerWidth / 2 - 250, y: 200 }}
>
  <div className="text-center py-4">
    <AlertTriangle className="h-12 w-12 text-red-500 mx-auto mb-4" />
    <p className="text-lg font-semibold mb-2">¿Eliminar configuración?</p>
    <p className="text-sm text-muted-foreground mb-4">
      Esta acción eliminará la configuración de precios para este país. No se puede deshacer.
    </p>
    <div className="flex justify-center gap-2">
      <Button variant="outline" onClick={() => setDialogoEliminarConfig(null)}>Cancelar</Button>
      <Button variant="destructive" onClick={handleEliminarConfig}>
        <Trash2 className="h-4 w-4 mr-2" /> Eliminar
      </Button>
    </div>
  </div>
</DraggableWindow>"""

new_block = """{/* ════════════════════════════════════════════════════
    MODAL ELIMINAR CONFIGURACIÓN (AlertDialog estándar)
    ════════════════════════════════════════════════════ */}
<AlertDialog open={!!dialogoEliminarConfig} onOpenChange={() => setDialogoEliminarConfig(null)}>
  <AlertDialogContent className="z-[70]">
    <AlertDialogHeader>
      <AlertDialogTitle className="flex items-center gap-2 text-red-600">
        <AlertTriangle className="h-5 w-5" />
        ¿Eliminar configuración?
      </AlertDialogTitle>
      <AlertDialogDescription>
        Esta acción eliminará la configuración de precios para este país. No se puede deshacer.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel onClick={() => setDialogoEliminarConfig(null)}>Cancelar</AlertDialogCancel>
      <AlertDialogAction onClick={handleEliminarConfig} className="bg-red-600 hover:bg-red-700 text-white">
        <Trash2 className="h-4 w-4 mr-2" />
        Eliminar
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("✅ Archivo corregido exitosamente.")
else:
    print("❌ No se encontró el bloque exacto. Buscando variaciones...")
    # Try to find and replace any variation
    import re
    pattern = r'<DraggableWindow\s+isOpen=\{!!dialogoEliminarConfig\}.*?onClose=\{\(\) => setDialogoEliminarConfig\(null\)\}.*?title="Eliminar Configuración".*?</DraggableWindow>'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_block + content[match.end():]
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print("✅ Archivo corregido con regex.")
    else:
        print("❌ No se pudo encontrar el bloque. Verifica el archivo manualmente.")
