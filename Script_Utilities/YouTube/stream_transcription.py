import os
from googleapiclient.discovery import build
from youtube_transcript_api import YouTubeTranscriptApi, TranscriptsDisabled, NoTranscriptFound

# Función para obtener detalles de los videos de un canal
def get_video_details(api_key, channel_id, max_results=100):
    youtube = build('youtube', 'v3', developerKey=api_key)
    video_details = []
    next_page_token = None
    results_retrieved = 0

    while results_retrieved < max_results:
        request = youtube.search().list(
            part='id,snippet',
            channelId=channel_id,
            maxResults=min(max_results - results_retrieved, 50),  # Solicitar hasta 50 resultados a la vez
            order='date',
            pageToken=next_page_token
        )
        response = request.execute()
        results_retrieved += len(response['items'])

        for item in response['items']:
            if item['id']['kind'] == 'youtube#video':
                video_details.append({
                    'id': item['id']['videoId'],
                    'title': item['snippet']['title']
                })

        next_page_token = response.get('nextPageToken')
        if not next_page_token:
            break

    return video_details

# Función para verificar si un video en vivo ha terminado
def is_finished_live_video(api_key, video_id):
    youtube = build('youtube', 'v3', developerKey=api_key)
    request = youtube.videos().list(
        part='liveStreamingDetails,snippet',
        id=video_id
    )
    response = request.execute()

    if 'liveStreamingDetails' in response['items'][0]:
        live_status = response['items'][0]['snippet']['liveBroadcastContent']
        actual_end_time = response['items'][0]['liveStreamingDetails'].get('actualEndTime', None)
        print(f"Video ID: {video_id} - Live Status: {live_status} - Actual End Time: {actual_end_time}")
        if live_status == 'none' and actual_end_time is not None:
            return True
    return False

# Función para descargar la transcripción de un video
def download_transcript(video_id, video_title, save_dir, lang='es'):
    try:
        transcript = YouTubeTranscriptApi.get_transcript(video_id, languages=[lang])
        transcription_text = ' '.join([segment['text'] for segment in transcript])

        with open(os.path.join(save_dir, f"{video_title}_{lang}.txt"), 'w', encoding='utf-8') as file:
            file.write(transcription_text)

        print(f"Transcripción descargada para {video_title} en {lang}")
    except (TranscriptsDisabled, NoTranscriptFound):
        print(f"No hay transcripción para {video_title} en {lang}")
    except Exception as e:
        print(f"Ocurrió un error con el video {video_title}: {e}")

# Función principal para obtener y descargar transcripciones de transmisiones en vivo finalizadas
def main(api_key, channel_id, save_dir, max_results=100, lang='es'):
    if not os.path.exists(save_dir):
        os.makedirs(save_dir)

    video_details = get_video_details(api_key, channel_id, max_results)
    finished_live_videos = [video for video in video_details if is_finished_live_video(api_key, video['id'])]

    for video in finished_live_videos:
        video_id = video['id']
        video_title = video['title']
        try:
            download_transcript(video_id, video_title, save_dir, lang)
        except Exception as e:
            print(f"Error al procesar {video_title}: {e}")
            continue

# Ejecución del script
if __name__ == "__main__":
    API_KEY = 'TU_API_KEY'
    CHANNEL_ID = 'TU_CHANNEL_ID'
    SAVE_DIR = 'TU_DIRECTORIO_DE_GUARDADO'
    MAX_RESULTS = 100  # Ajustar según sea necesario

    main(API_KEY, CHANNEL_ID, SAVE_DIR, max_results=MAX_RESULTS, lang='es')
