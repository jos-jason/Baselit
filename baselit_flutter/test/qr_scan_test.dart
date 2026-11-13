// Checks that printed Baselit labels decode and resolve, from a photo and from
// a raw webcam frame like the Linux scanner reads.

import 'dart:io';
import 'dart:typed_data';

import 'package:baselit/models.dart';
import 'package:baselit/scanner.dart';
import 'package:baselit/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart' as zx;

/// A QR code drawn on a white page, like a label in a photo.
img.Image _label(String payload, {int width = 640, int height = 480}) {
  final matrix = zx.Encoder.encode(payload, zx.ErrorCorrectionLevel.m).matrix!;
  const scale = 6;
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(235, 235, 230, 255));
  final left = (width - matrix.width * scale) ~/ 2;
  final top = (height - matrix.height * scale) ~/ 2;
  for (var x = 0; x < matrix.width; x++) {
    for (var y = 0; y < matrix.height; y++) {
      if (matrix.get(x, y) == 1) {
        img.fillRect(
          image,
          x1: left + x * scale,
          y1: top + y * scale,
          x2: left + x * scale + scale - 1,
          y2: top + y * scale + scale - 1,
          color: img.ColorRgba8(20, 20, 20, 255),
        );
      }
    }
  }
  return image;
}

void main() {
  final store = InventoryStore()..loaded = true;
  final bin = StorageContainer(name: 'Tool Bin', identifier: 'Bright Falcon');
  final drill = Item(name: 'Drill', identifier: 'Calm Otter');
  store
    ..containers = [bin]
    ..items = [drill];

  test('looks up labels the same way as iOS', () {
    expect(store.lookupQRPayload('baselit:container:bright-falcon'), bin);
    expect(store.lookupQRPayload('baselit:item:calm-otter'), drill);
    expect(store.lookupQRPayload('baselit:item:lost-heron'), isNull);
    expect(
      () => store.lookupQRPayload('https://example.com'),
      throwsFormatException,
    );
    expect(
      () => store.lookupQRPayload('baselit:house:x'),
      throwsFormatException,
    );
  });

  test('decodes a label from a photo', () {
    final dir = Directory.systemTemp.createTempSync('qr');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/label.jpg')
      ..writeAsBytesSync(
        img.encodeJpg(
          _label('baselit:item:calm-otter', width: 3000, height: 2200),
        ),
      );
    expect(decodeQRFile(file.path), 'baselit:item:calm-otter');
  });

  test('decodes a BGRA webcam frame', () {
    final frame = _label('baselit:container:bright-falcon')
        .getBytes(order: img.ChannelOrder.bgra);
    final pixels = Uint8List.fromList(frame).buffer.asInt32List();
    expect(decodeQRPixels(640, 480, pixels), 'baselit:container:bright-falcon');
    expect(decodeQRPixels(640, 480, Int32List(640 * 480)), isNull);
  });
}
