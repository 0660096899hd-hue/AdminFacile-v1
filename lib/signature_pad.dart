import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<Offset?> _points = <Offset?>[];
  bool _saving = false;

  Future<void> _save() async {
    if (_points.whereType<Offset>().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Dessinez votre signature avant de l’enregistrer.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || data == null) return;
      Navigator.of(context).pop(Uint8List.view(data.buffer));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dessiner ma signature')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text('Signez avec votre doigt dans la zone blanche.'),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: Container(
                        key: const Key('signature-drawing-area'),
                        color: Colors.transparent,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) => setState(
                              () => _points.add(details.localPosition)),
                          onPanUpdate: (details) => setState(
                              () => _points.add(details.localPosition)),
                          onPanEnd: (_) => setState(() => _points.add(null)),
                          child: CustomPaint(
                            painter: SignaturePainter(_points),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => setState(_points.clear),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Effacer'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('save-signature-drawing'),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Enregistrer'),
                ),
              ]),
            ]),
          ),
        ),
      );
}

class SignaturePainter extends CustomPainter {
  const SignaturePainter(this.points);
  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF071B3A)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var index = 0; index < points.length - 1; index++) {
      final first = points[index];
      final second = points[index + 1];
      if (first != null && second != null) {
        canvas.drawLine(first, second, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
