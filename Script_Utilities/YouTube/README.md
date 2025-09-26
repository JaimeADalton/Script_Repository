# YouTube

Scripts para descargar transcripciones de videos de YouTube usando la API oficial.

## Scripts

### `stream_transcription.py`
- **Funcionalidad:** identifica transmisiones en vivo finalizadas de un canal y descarga transcripciones en el idioma indicado.
- **Precisión:** requiere API key de Google y gestiona excepciones `TranscriptsDisabled`/`NoTranscriptFound`. Usa `youtube_transcript_api` y la API Data v3.
- **Complejidad:** media.
- **Manual de uso:**
  1. Instalar dependencias (`pip install google-api-python-client youtube-transcript-api`).
  2. Configurar `API_KEY`, `CHANNEL_ID`, `SAVE_DIR` y ejecutar el script.
  3. Las transcripciones se guardan como `<título>_<lang>.txt`.

### `video_transcription.py`
- **Funcionalidad:** recorre videos subidos de un canal, limpia títulos para uso como nombre de archivo y guarda transcripciones.
- **Precisión:** mismo manejo de errores que el script anterior.
- **Complejidad:** media.
- **Manual de uso:** igual que el script de streams pero aplicable a videos publicados.
