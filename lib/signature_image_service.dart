import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Normalise une signature dessinée ou photographiée en PNG transparent.
class SignatureImageService {
  const SignatureImageService._();

  static const int transparentMargin = 6;

  static bool hasOpaqueLightBackground(Uint8List source) {
    final image = img.decodeImage(source)?.convert(numChannels: 4);
    if (image == null) return true;
    var inspected = 0;
    var opaqueLight = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (x > 1 && x < image.width - 2 && y > 1 && y < image.height - 2) {
          continue;
        }
        final pixel = image.getPixel(x, y);
        inspected++;
        if (pixel.a.toInt() > 240 &&
            pixel.r.toInt() > 235 &&
            pixel.g.toInt() > 235 &&
            pixel.b.toInt() > 235) {
          opaqueLight++;
        }
      }
    }
    return inspected > 0 && opaqueLight / inspected > .6;
  }

  static Future<Uint8List> normalizeSignatureToTransparentPng(
      Uint8List source) async {
    var image = img.decodeImage(source);
    if (image == null) {
      throw const FormatException('Image de signature illisible.');
    }
    if (image.width > 2048) {
      image = img.copyResize(image, width: 2048);
    }
    image = image.convert(numChannels: 4);

    var minX = image.width;
    var minY = image.height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final red = pixel.r.toInt();
        final green = pixel.g.toInt();
        final blue = pixel.b.toInt();
        final sourceAlpha = pixel.a.toInt();

        // La distance au blanc préserve les traits colorés et les contours
        // anti-crénelés, tout en supprimant le papier blanc ou très clair.
        final lightestChannel = red < green
            ? (red < blue ? red : blue)
            : (green < blue ? green : blue);
        final allChannelsAlmostWhite = red > 235 && green > 235 && blue > 235;
        final backgroundAlpha = allChannelsAlmostWhite
            ? 0
            : lightestChannel <= 205
                ? 255
                : ((235 - lightestChannel) * 255 ~/ 30).clamp(0, 255);
        final alpha = sourceAlpha * backgroundAlpha ~/ 255;
        // Mettre aussi RGB à zéro lorsque alpha vaut zéro évite les franges
        // blanches dues à l'interpolation/premultiplication dans le PDF.
        image.setPixelRgba(x, y, alpha == 0 ? 0 : red, alpha == 0 ? 0 : green,
            alpha == 0 ? 0 : blue, alpha);

        if (alpha > 8) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      throw const FormatException('Aucun trait de signature détecté.');
    }

    final cropLeft = (minX - transparentMargin).clamp(0, image.width - 1);
    final cropTop = (minY - transparentMargin).clamp(0, image.height - 1);
    final cropRight = (maxX + transparentMargin).clamp(0, image.width - 1);
    final cropBottom = (maxY + transparentMargin).clamp(0, image.height - 1);
    final cropped = img.copyCrop(
      image,
      x: cropLeft,
      y: cropTop,
      width: cropRight - cropLeft + 1,
      height: cropBottom - cropTop + 1,
    );
    return Uint8List.fromList(img.encodePng(cropped, level: 6));
  }
}
