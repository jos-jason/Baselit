// QR label scanner. Android and Mac use the live camera through mobile_scanner.
// Linux has no Flutter camera plugin, so it reads webcam frames from ffmpeg and
// decodes them with zxing2. Every platform can also scan a photo of a label.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart' as zx;

/// Opens the scanner full screen and returns the scanned text, or null if cancelled.
Future<String?> scanQRCode(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QRScannerScreen(),
      ),
    );

/// Decodes a QR code from ARGB pixels, or returns null if none is found.
String? decodeQRPixels(int width, int height, Int32List argb) {
  final source = zx.RGBLuminanceSource(width, height, argb);
  for (final bitmap in [
    zx.BinaryBitmap(zx.HybridBinarizer(source)),
    zx.BinaryBitmap(zx.GlobalHistogramBinarizer(source)),
  ]) {
    try {
      return zx.QRCodeReader().decode(bitmap).text;
    } on zx.ReaderException {
      continue;
    }
  }
  return null;
}

/// Decodes a QR code from a PNG, JPEG, WebP, BMP, or GIF file.
String? decodeQRFile(String path) {
  var image = img.decodeImage(File(path).readAsBytesSync());
  if (image == null) return null;
  // Phone photos are large; a label still reads fine at this size and decodes much faster
  if (image.width > 1200 || image.height > 1200) {
    image = image.width > image.height
        ? img.copyResize(image, width: 1200)
        : img.copyResize(image, height: 1200);
  }
  final argb = image
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.bgra)
      .buffer
      .asInt32List();
  return decodeQRPixels(image.width, image.height, argb);
}

// Top-level so the isolate closures capture nothing but their arguments
Future<String?> _decodeFileInBackground(String path) =>
    Isolate.run(() => decodeQRFile(path));

Future<String?> _decodePixelsInBackground(
  int width,
  int height,
  Uint8List bgra,
) =>
    Isolate.run(() => decodeQRPixels(width, height, bgra.buffer.asInt32List()));

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _done = false;
  String? _message;

  void _finish(String code) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  Future<void> _scanPhoto() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    if (file == null) return;
    final path = file.path;
    final code = await _decodeFileInBackground(path);
    if (code != null) {
      _finish(code);
    } else if (mounted) {
      setState(() => _message = 'No QR code found in that photo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = Platform.isLinux
        ? _LinuxWebcam(onCode: _finish)
        : MobileScanner(
            controller: MobileScannerController(
              formats: const [BarcodeFormat.qrCode],
            ),
            onDetect: (capture) {
              final value = capture.barcodes
                  .map((b) => b.rawValue)
                  .nonNulls
                  .firstOrNull;
              if (value != null) _finish(value);
            },
            errorBuilder: (context, error) => _CameraMessage(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Baselit needs camera access to scan labels. Allow it in your system settings, or scan a photo instead.'
                  : 'The camera isn\'t available. You can scan a photo of the label instead.',
            ),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          camera,
          const IgnorePointer(child: _Viewfinder()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      TextButton.icon(
                        onPressed: _scanPhoto,
                        icon: const Icon(CupertinoIcons.photo),
                        label: const Text('From Photo'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded square guide in the middle of the camera view.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white70, width: 3),
        borderRadius: BorderRadius.circular(26),
      ),
    ),
  );
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.camera, size: 44, color: Colors.white54),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    ),
  );
}

// MARK: - Linux webcam

/// Streams 640×480 BGRA frames from the first webcam through ffmpeg, shows
/// them, and decodes the newest frame whenever the previous decode finishes.
class _LinuxWebcam extends StatefulWidget {
  const _LinuxWebcam({required this.onCode});

  final void Function(String) onCode;

  @override
  State<_LinuxWebcam> createState() => _LinuxWebcamState();
}

class _LinuxWebcamState extends State<_LinuxWebcam> {
  static const width = 640;
  static const height = 480;
  static const frameBytes = width * height * 4;

  Process? _ffmpeg;
  StreamSubscription<List<int>>? _output;
  final _buffer = BytesBuilder(copy: false);
  ui.Image? _frame;
  bool _decoding = false;
  bool _converting = false;
  String? _error;
  final _stderr = StringBuffer();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _output?.cancel();
    _ffmpeg?.kill();
    _frame?.dispose();
    super.dispose();
  }

  String? get _device {
    for (var i = 0; i < 10; i++) {
      if (File('/dev/video$i').existsSync()) return '/dev/video$i';
    }
    return null;
  }

  Future<void> _start() async {
    final device = _device;
    if (device == null) {
      setState(
        () => _error =
            'No webcam found. You can scan a photo of the label instead.',
      );
      return;
    }
    try {
      _ffmpeg = await Process.start('ffmpeg', [
        '-loglevel',
        'error',
        '-f',
        'v4l2',
        '-video_size',
        '${width}x$height',
        '-i',
        device,
        '-vf',
        'scale=$width:$height',
        '-r',
        '15',
        '-pix_fmt',
        'bgra',
        '-f',
        'rawvideo',
        '-',
      ]);
    } on ProcessException {
      setState(
        () => _error = 'Scanning with the webcam needs ffmpeg. Install it with:\nsudo pacman -S ffmpeg\n\nOr scan a photo of the label instead.',
      );
      return;
    }
    _ffmpeg!.stderr.listen((data) => _stderr.write(String.fromCharCodes(data)));
    _ffmpeg!.exitCode.then((code) {
      if (mounted && code != 0 && _error == null) {
        setState(
          () => _error =
              'The webcam couldn\'t be opened. ${_stderr.toString().trim()}',
        );
      }
    });
    _output = _ffmpeg!.stdout.listen(_onData);
  }

  void _onData(List<int> data) {
    _buffer.add(data);
    if (_buffer.length < frameBytes) return;
    final bytes = _buffer.takeBytes();
    // Keep only the newest complete frame and carry over any partial one
    final complete = bytes.length ~/ frameBytes;
    final start = (complete - 1) * frameBytes;
    final frame = Uint8List.sublistView(bytes, start, start + frameBytes);
    final rest = bytes.length - complete * frameBytes;
    if (rest > 0) {
      _buffer.add(Uint8List.sublistView(bytes, bytes.length - rest));
    }
    final pixels = Uint8List.fromList(frame);
    _show(pixels);
    _decode(pixels);
  }

  void _show(Uint8List pixels) {
    if (_converting) return;
    _converting = true;
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.bgra8888, (
      image,
    ) {
      _converting = false;
      if (!mounted) return image.dispose();
      setState(() {
        _frame?.dispose();
        _frame = image;
      });
    });
  }

  Future<void> _decode(Uint8List pixels) async {
    if (_decoding) return;
    _decoding = true;
    final code = await _decodePixelsInBackground(width, height, pixels);
    _decoding = false;
    if (code != null && mounted) widget.onCode(code);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _CameraMessage(_error!);
    final frame = _frame;
    if (frame == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        // Mirrored like a selfie camera; decoding uses the unmirrored frame
        child: Transform.flip(flipX: true, child: RawImage(image: frame)),
      ),
    );
  }
}
