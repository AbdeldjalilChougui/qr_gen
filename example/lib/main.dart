import 'package:flutter/material.dart';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:qr_gen/qr_gen.dart';

void main() => runApp(const QrGenExampleApp());

/// Demonstrates qr_gen: live encoding, styles, embedded image, export.
class QrGenExampleApp extends StatelessWidget {
  /// Creates the app.
  const QrGenExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'qr_gen example',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const QrDemoPage(),
      );
}

/// The single demo page.
class QrDemoPage extends StatefulWidget {
  /// Creates the page.
  const QrDemoPage({super.key});

  @override
  State<QrDemoPage> createState() => _QrDemoPageState();
}

class _QrDemoPageState extends State<QrDemoPage> {
  final _controller =
      TextEditingController(text: 'https://pub.dev/packages/qr_gen');
  QrEcLevel _level = QrEcLevel.medium;
  QrModuleShape _eye = QrModuleShape.square;
  QrModuleShape _module = QrModuleShape.square;
  bool _logo = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copySvg() async {
    final matrix = QrEncoder.encode(_controller.text, ecLevel: _level);
    await Clipboard.setData(ClipboardData(text: matrix.toSvg()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('SVG copied (version ${matrix.version}, '
            'mask ${matrix.mask})')));
  }

  Future<void> _exportPng() async {
    final painter =
        QrPainter(data: _controller.text, errorCorrectionLevel: _level);
    final bytes = await painter.toImageData(512);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rendered a 512 x 512 PNG: '
            '${bytes?.lengthInBytes ?? 0} bytes')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('qr_gen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: QrImageView(
              data: _controller.text,
              size: 240,
              errorCorrectionLevel: _level,
              eyeStyle: QrEyeStyle(shape: _eye, color: Colors.teal.shade900),
              dataModuleStyle: QrDataModuleStyle(shape: _module),
              embeddedImage: _logo ? const _LogoImage() : null,
              embeddedImageStyle:
                  const QrEmbeddedImageStyle(size: Size(48, 48)),
              semanticsLabel: 'QR code for ${_controller.text}',
              errorStateBuilder: (context, error) => const SizedBox.square(
                dimension: 240,
                child: Center(child: Text('Too much data for a QR code')),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Data', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _choice<QrEcLevel>('Error correction', QrEcLevel.values, _level,
              (v) => setState(() => _level = v)),
          _choice<QrModuleShape>('Eyes', QrModuleShape.values, _eye,
              (v) => setState(() => _eye = v)),
          _choice<QrModuleShape>('Modules', QrModuleShape.values, _module,
              (v) => setState(() => _module = v)),
          SwitchListTile(
            title: const Text('Embedded logo (use level Q or H)'),
            value: _logo,
            onChanged: (v) => setState(() {
              _logo = v;
              if (v) _level = QrEcLevel.high;
            }),
          ),
          Wrap(spacing: 8, children: [
            FilledButton.tonal(
                onPressed: _copySvg, child: const Text('Copy SVG')),
            FilledButton.tonal(
                onPressed: _exportPng, child: const Text('Export PNG')),
          ]),
        ],
      ),
    );
  }

  Widget _choice<T extends Enum>(
      String label, List<T> values, T selected, ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Wrap(spacing: 4, children: [
            for (final v in values)
              ChoiceChip(
                label: Text(v.name),
                selected: v == selected,
                onSelected: (_) => onChanged(v),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A tiny generated logo, so the example needs no asset files.
class _LogoImage extends ImageProvider<_LogoImage> {
  const _LogoImage();

  @override
  Future<_LogoImage> obtainKey(ImageConfiguration configuration) =>
      Future.value(this);

  @override
  ImageStreamCompleter loadImage(_LogoImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_draw());

  static Future<ImageInfo> _draw() async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 96, 96), const Radius.circular(20)),
        Paint()..color = Colors.teal);
    canvas.drawCircle(const Offset(48, 48), 22, Paint()..color = Colors.white);
    final image = await recorder.endRecording().toImage(96, 96);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) => other is _LogoImage;

  @override
  int get hashCode => 0;
}
