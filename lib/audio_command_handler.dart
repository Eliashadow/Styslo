import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:logger/logger.dart';

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       
    errorMethodCount: 5,  
    lineLength: 80,       
    colors: true,         
  ),
);

class AudioCommandHandler extends BaseAudioHandler with SeekHandler {
  Function? onPlayTriggered;
  Function? onPauseTriggered;
  Function? onNextTriggered;
  Function? onPreviousTriggered;

  AudioCommandHandler() {
    _activateAudioService();

    mediaItem.add(const MediaItem(
      id: 'styslo_audio_service',
      album: 'Styslo Reader',
      title: 'Voice Session Active', 
    ));

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play, 
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.playPause,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: [0, 1, 2], 
      playing: false,
      processingState: AudioProcessingState.ready,
    ));
  }


Future<void> _activateAudioService() async {
  final session = await AudioSession.instance;
  await session.setActive(true);

  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech, 
      usage: AndroidAudioUsage.media,              
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  ));
  await session.setActive(true);

  session.becomingNoisyEventStream.listen((_) {
    logger.i('[HEADSET] Becoming noisy event: Pausing audio');
    pause(); 
  });

  session.interruptionEventStream.listen((event) {
    if (event.begin) {
      logger.i('[HEADSET] Something happened(mostly cause of incoming call), so stopping');
      pause();
    }
  });
  bool success = await session.setActive(true);
  if (!success) {
    logger.e("[AUDIO] Failed to gain audio focus!");
  }

}

  void updatePlaybackState(bool isPlaying) {
    logger.i('[HEADSET] Playing status in updatePlaybackState: $isPlaying');
    playbackState.add(playbackState.value.copyWith(
      playing: isPlaying,
      controls: [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seek,
    },
      processingState:  AudioProcessingState.ready,
    ));
  }

  @override
  Future<void> play() async {
    logger.i('[DEBUG] AudioHandler.play() received!');
    if (onPlayTriggered != null) onPlayTriggered!();
  }

  @override
  Future<void> pause() async {
    logger.i('[DEBUG] AudioHandler.pause() received!');
    if (onPauseTriggered != null) onPauseTriggered!();
  }

  @override
  Future<void> skipToNext() async {
    if (onNextTriggered != null) onNextTriggered!();
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPreviousTriggered != null) onPreviousTriggered!();
  }
}