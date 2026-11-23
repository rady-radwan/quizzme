import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech using the device's own speech engine (works offline when
/// the device has an offline voice installed) and playback of imported audio.
class SpeechService {
  FlutterTts? _tts;
  AudioPlayer? _player;
  double rate = 0.5;

  static final RegExp _arabic = RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿ]');

  FlutterTts get _engine => _tts ??= FlutterTts();

  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await _engine.stop();
      await _engine.setLanguage(_arabic.hasMatch(t) ? 'ar' : 'en-US');
      await _engine.setSpeechRate(rate);
      await _engine.speak(t);
    } catch (e) {
      debugPrint('Text-to-speech unavailable: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  Future<void> playFile(File file, {double speed = 1.0}) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(DeviceFileSource(file.path));
      await player.setPlaybackRate(speed);
    } catch (e) {
      debugPrint('Audio playback failed: $e');
    }
  }

  Future<void> stopAudio() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopSpeaking();
    await _player?.dispose();
    _player = null;
  }
}
