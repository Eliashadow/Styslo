// This code handles headphones command and activates audio service(gaining focus)
// ---- Audio imports ----
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
// ---- Log imports ----
import 'package:logger/logger.dart';

// ---- Log ----
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       
    errorMethodCount: 5,  
    lineLength: 80,       
    colors: true,         
  ),
);

// 
class AudioCommandHandler extends BaseAudioHandler with SeekHandler {
  // Handling commands from headphones
  Function? onPlayTriggered;
  Function? onPauseTriggered;
  Function? onNextTriggered;
  Function? onPreviousTriggered;

  AudioCommandHandler() {
    _activateAudioService();

    // Adding notification on screen
    mediaItem.add(const MediaItem(
      id: 'styslo_audio_service',
      album: 'Styslo Reader',
      title: 'Voice Session Active', 
    ));

    // Initializating used command futher actions 
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
      // Order of controls
      androidCompactActionIndices: [0, 1, 2], 
      playing: false,
      processingState: AudioProcessingState.ready,
    ));
  }

  // Initializating audio service
  Future<void> _activateAudioService() async {
    final session = await AudioSession.instance;
    // Activating session
    await session.setActive(true);
    // Configuring options 
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech, 
        usage: AndroidAudioUsage.media,              
      ),
      // This is crucial for headphones to work with audio(without correct gaining focus, it will remain in other apps, so it will not work)
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    // Applying options
    await session.setActive(true);

    // Stopping audio because of disconneting headphones
    session.becomingNoisyEventStream.listen((_) {
      logger.i('[HEADSET] Becoming noisy event: Pausing audio');
      pause(); 
    });

    // Stopping audio because of another audio 
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        logger.i('[HEADSET] Something happened(mostly cause of incoming call), so stopping');
        pause();
      }
    });

    // Checking for correct applying options 
    bool success = await session.setActive(true);
    if (!success) {
      logger.e("[AUDIO] Failed to gain audio focus!");
    }
  }
  
  // Updating state
  void updatePlaybackState(bool isPlaying) {
    logger.i('[HEADSET] Playing status in updatePlaybackState: $isPlaying');

    // Adding crucial values
    playbackState.add(playbackState.value.copyWith(
      playing: isPlaying,
      // Updating notification with isPlaying 
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

  // Processing headphones commands
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