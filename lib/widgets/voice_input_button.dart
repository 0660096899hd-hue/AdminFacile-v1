import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.controller,
    this.localeId,
  });

  final TextEditingController controller;
  final String? localeId;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final SpeechToText _speech = SpeechToText();

  bool _listening = false;
  String _initialText = '';

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();

      if (mounted) {
        setState(() => _listening = false);
      }
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;

        if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _listening = false);
        }
      },
    );

    if (!available || !mounted) return;

    _initialText = widget.controller.text.trim();

    setState(() => _listening = true);

    await _speech.listen(
      onResult: (result) {
        final spokenText = result.recognizedWords.trim();
        if (spokenText.isEmpty) return;

        final separator = _initialText.isEmpty ? '' : ' ';
        final completeText = '$_initialText$separator$spokenText';

        widget.controller
          ..text = completeText
          ..selection = TextSelection.collapsed(
            offset: completeText.length,
          );
      },
      listenOptions: SpeechListenOptions(
        localeId: widget.localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening ? 'Arrêter la dictée' : 'Dicter ce texte',
      onPressed: _toggle,
      icon: Icon(
        _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
        color: _listening
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
