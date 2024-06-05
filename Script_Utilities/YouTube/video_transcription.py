    except Exception as e:
        print(f"Ocurrió un error con el video {video_title}: {e}")

# Función principal para obtener y descargar transcripciones de videos subidos
def main(api_key, channel_id, save_dir, max_results=100, lang='es'):
    if not os.path.exists(save_dir):
        os.makedirs(save_dir)

    video_details = get_video_details(api_key, channel_id, max_results)

    for video in video_details:
        video_url = video['url']
        video_title = video['title']
        video_id = video_url.split('v=')[1]
        download_transcript(video_id, video_title, save_dir, lang)


# Ejecución del script
if __name__ == "__main__":
    API_KEY = 'TU_API_KEY'
    CHANNEL_ID = 'TU_CHANNEL_ID'
    SAVE_DIR = 'TU_DIRECTORIO_DE_GUARDADO'
    MAX_RESULTS = 100  # Ajustar según sea necesario

    main(API_KEY, CHANNEL_ID, SAVE_DIR, max_results=MAX_RESULTS, lang='es')
