import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';

/// Shows a question's image (tap to zoom) and an audio play button.
class QuestionMedia extends StatelessWidget {
  const QuestionMedia({super.key, required this.question});
  final Question question;

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.I;
    final image = svc.media.resolve(question.imagePath);
    final audio = svc.media.resolve(question.audioPath);
    if (image == null && audio == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (image != null)
          Semantics(
            image: true,
            label: 'Question image. Double tap to enlarge.',
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(),
                    backgroundColor: Colors.black,
                    body: InteractiveViewer(
                      maxScale: 6,
                      child: Center(child: Image.file(image, errorBuilder: (_, __, ___) => const _Missing())),
                    ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: Image.file(image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const _Missing()),
                ),
              ),
            ),
          ),
        if (audio != null) ...[
          if (image != null) const SizedBox(height: 8),
          _AudioRow(path: question.audioPath!),
        ],
      ]),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Row(children: [Icon(Icons.broken_image_outlined), SizedBox(width: 8), Text('Image not available')]),
      );
}

class _AudioRow extends StatefulWidget {
  const _AudioRow({required this.path});
  final String path;

  @override
  State<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends State<_AudioRow> {
  double _speed = 1.0;

  @override
  void dispose() {
    AppServices.I.speech.stopAudio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.I;
    final file = svc.media.resolve(widget.path);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          IconButton.filled(
            tooltip: 'Play audio',
            icon: const Icon(Icons.play_arrow),
            onPressed: file == null ? null : () => svc.speech.playFile(file, speed: _speed),
          ),
          IconButton(
            tooltip: 'Stop',
            icon: const Icon(Icons.stop),
            onPressed: () => svc.speech.stopAudio(),
          ),
          const SizedBox(width: 8),
          const Text('Speed'),
          Expanded(
            child: Slider(
              value: _speed,
              min: 0.5,
              max: 1.5,
              divisions: 4,
              label: '${_speed}x',
              onChanged: (v) => setState(() => _speed = v),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Read-aloud button using the device text-to-speech engine.
class SpeakButton extends StatelessWidget {
  const SpeakButton({super.key, required this.text, this.tooltip = 'Read aloud'});
  final String text;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        icon: const Icon(Icons.volume_up_outlined),
        onPressed: () => AppServices.I.speech.speak(text),
      );
}
