import fitz  # PyMuPDF

def censurar_pdf(pdf_path, output_path, word_to_censor):
    # Abrir el PDF original para edición
    doc = fitz.open(pdf_path)

    for page_num in range(len(doc)):
        page = doc.load_page(page_num)
        text_instances = page.search_for(word_to_censor)

        # Cubrir cada instancia de la palabra
        for inst in text_instances:
            # Crear un rectángulo que cubra toda la línea
            # El rectángulo se extiende a lo ancho de la página
            rect = fitz.Rect(0, inst[1], page.rect.width, inst[3])
            page.add_redact_annot(rect, fill=(1, 1, 1))

        # Aplicar las redacciones
        page.apply_redactions()

    # Guardar el PDF editado
    doc.save(output_path)
    doc.close()

# Uso del método
censurar_pdf("H13-611_V5.0.pdf", "H13-611_V5.0_censurado.pdf", "Answer")
