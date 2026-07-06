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
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech, // Tells Android this is speech
      usage: AndroidAudioUsage.media,              // Tells Android to treat it like media for button routing
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  ));

  session.becomingNoisyEventStream.listen((_) {
    logger.i('[HEADSET DEBUG] Becoming noisy event: Pausing audio');
    pause(); 
  });

  bool success = await session.setActive(true);
  if (!success) {
    logger.e("[AUDIO DEBUG] Failed to gain audio focus!");
  }

}

  void updatePlaybackState(bool isPlaying) {
    playbackState.add(playbackState.value.copyWith(
      playing: isPlaying,
      controls: [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      processingState: AudioProcessingState.ready,


    ));
  }

  // 1. ADD THIS OVERRIDE: This intercepts the physical headphone button click!
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    logger.d('[HEADSET DEBUG] Button pressed: $button');
    switch (button) {
      case MediaButton.media:
        // If it's a standard single-button click, toggle the state
        if (playbackState.value.playing) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
    await super.click(button);
  }

  @override
  Future<void> play() async {
    updatePlaybackState(true);
    if (onPlayTriggered != null) onPlayTriggered!();
  }

  @override
  Future<void> pause() async {
    // 3. Update the state so the OS knows we are paused
    updatePlaybackState(false);
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