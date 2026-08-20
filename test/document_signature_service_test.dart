import 'dart:io';
import 'dart:typed_data';

import 'package:admin_facile/document_signature_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int width, int height, {bool transparent = false}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image,
      color: transparent
          ? img.ColorRgba8(0, 0, 0, 0)
          : img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(image,
      x1: 4,
      y1: 4,
      x2: width - 5,
      y2: height - 5,
      color: img.ColorRgba8(20, 80, 180, 220));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('placement uses normalized coordinates and stays on the page', () {
    const placement = NormalizedSignaturePlacement(
        pageIndex: 0, x: .8, y: .9, width: .3, height: .2);
    final bounded = placement.constrained();
    expect(bounded.x + bounded.width, lessThanOrEqualTo(1));
    expect(bounded.y + bounded.height, lessThanOrEqualTo(1));
    expect(bounded.x, greaterThanOrEqualTo(0));
    expect(bounded.y, greaterThanOrEqualTo(0));
  });

  test('move and pinch resize preserve the signature ratio', () {
    const placement = NormalizedSignaturePlacement(
        pageIndex: 0, x: .2, y: .3, width: .25, height: .1);
    final transformed = placement.transform(
        deltaX: .15,
        deltaY: -.1,
        scale: 1.5,
        pageAspectRatio: .7,
        signatureAspectRatio: 2.5);
    expect(transformed.width, closeTo(.375, .0001));
    expect(transformed.height, closeTo(transformed.width * .7 / 2.5, .0001));
    expect(transformed.x, isNot(placement.x));
  });

  test('resize handle grows and shrinks while preserving ratio', () {
    const placement = NormalizedSignaturePlacement(
        pageIndex: 0, x: .2, y: .2, width: .3, height: .084);
    final grown = placement.resizeFromBottomRight(
      deltaWidth: .2,
      pageAspectRatio: .7,
      signatureAspectRatio: 2.5,
    );
    final shrunk = grown.resizeFromBottomRight(
      deltaWidth: -.3,
      pageAspectRatio: .7,
      signatureAspectRatio: 2.5,
    );
    expect(grown.width, closeTo(.5, .0001));
    expect(grown.height / grown.width, closeTo(.7 / 2.5, .0001));
    expect(shrunk.width, closeTo(.2, .0001));
    expect(shrunk.height / shrunk.width, closeTo(.7 / 2.5, .0001));
  });

  test('resize handle enforces minimum maximum and page bounds', () {
    const placement = NormalizedSignaturePlacement(
        pageIndex: 0, x: .35, y: .7, width: .3, height: .084);
    final minimum = placement.resizeFromBottomRight(
      deltaWidth: -5,
      pageAspectRatio: .7,
      signatureAspectRatio: 2.5,
    );
    final maximum = placement.resizeFromBottomRight(
      deltaWidth: 5,
      pageAspectRatio: .7,
      signatureAspectRatio: 2.5,
    );
    expect(minimum.width, .08);
    expect(maximum.width, lessThanOrEqualTo(.65));
    expect(maximum.x + maximum.width, lessThanOrEqualTo(1));
    expect(maximum.y + maximum.height, lessThanOrEqualTo(1));
  });

  test('normalized size maps to exact PDF dimensions', () {
    const placement = NormalizedSignaturePlacement(
        pageIndex: 0, x: .1, y: .2, width: .35, height: .12);
    final rect = DocumentSignatureService.pdfRectForPlacement(
      placement,
      pageWidth: 600,
      pageHeight: 800,
    );
    expect(rect.left, 60);
    expect(rect.top, 160);
    expect(rect.width, 210);
    expect(rect.height, 96);
  });

  test('document zoom is clamped between 1x and 4x', () {
    expect(SignatureViewportTransform.clampZoom(.2), 1);
    expect(SignatureViewportTransform.clampZoom(2.5), 2.5);
    expect(SignatureViewportTransform.clampZoom(8), 4);
  });

  test('screen drag is converted through the current zoom', () {
    final atOne = SignatureViewportTransform.screenDeltaToNormalized(
      100,
      unscaledPageExtent: 500,
      zoom: 1,
    );
    final atTwo = SignatureViewportTransform.screenDeltaToNormalized(
      100,
      unscaledPageExtent: 500,
      zoom: 2,
    );
    expect(atOne, .2);
    expect(atTwo, .1);
  });

  test('zoom does not alter normalized placement or PDF coordinates', () {
    const placement = NormalizedSignaturePlacement(
        pageIndex: 0, x: .72, y: .81, width: .18, height: .06);
    final before = DocumentSignatureService.pdfRectForPlacement(
      placement,
      pageWidth: 600,
      pageHeight: 800,
    );
    SignatureViewportTransform.screenDeltaToNormalized(
      0,
      unscaledPageExtent: 500,
      zoom: 4,
    );
    final after = DocumentSignatureService.pdfRectForPlacement(
      placement,
      pageWidth: 600,
      pageHeight: 800,
    );
    expect(after.left, before.left);
    expect(after.top, before.top);
    expect(after.width, before.width);
    expect(after.height, before.height);
  });

  test('resize handle delta is reduced by zoom and preserves ratio', () {
    const placement = NormalizedSignaturePlacement(
        pageIndex: 0, x: .2, y: .2, width: .3, height: .084);
    final deltaAtTwo = SignatureViewportTransform.screenDeltaToNormalized(
      100,
      unscaledPageExtent: 500,
      zoom: 2,
    );
    final resized = placement.resizeFromBottomRight(
      deltaWidth: deltaAtTwo,
      pageAspectRatio: .7,
      signatureAspectRatio: 2.5,
    );
    expect(resized.width, closeTo(.4, .0001));
    expect(resized.height / resized.width, closeTo(.7 / 2.5, .0001));
  });

  test('a signed multipage copy is generated without modifying originals',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('adminfacile_signed_');
    addTearDown(() => directory.delete(recursive: true));
    final page1 = _png(300, 420);
    final page2 = _png(420, 300);
    final signature = _png(160, 60, transparent: true);
    final page1Before = Uint8List.fromList(page1);
    final signatureBefore = Uint8List.fromList(signature);
    final output = await DocumentSignatureService.createSignedCopy(
      pageImages: [page1, page2],
      signaturePng: signature,
      placements: const [
        NormalizedSignaturePlacement(
            pageIndex: 1, x: .45, y: .7, width: .35, height: .16),
      ],
      outputDirectory: directory,
    );
    expect(await File(output).exists(), isTrue);
    expect(await File(output).length(), greaterThan(1000));
    expect(page1, orderedEquals(page1Before));
    expect(signature, orderedEquals(signatureBefore));
  });

  test('only explicitly selected pages receive placements', () async {
    final directory =
        await Directory.systemTemp.createTemp('adminfacile_pages_');
    addTearDown(() => directory.delete(recursive: true));
    final output = await DocumentSignatureService.createSignedCopy(
      pageImages: [_png(120, 180), _png(120, 180), _png(120, 180)],
      signaturePng: _png(80, 30, transparent: true),
      placements: const [
        NormalizedSignaturePlacement(
            pageIndex: 0, x: .1, y: .7, width: .3, height: .1),
        NormalizedSignaturePlacement(
            pageIndex: 2, x: .5, y: .7, width: .3, height: .1),
      ],
      outputDirectory: directory,
    );
    expect(await File(output).length(), greaterThan(1000));
    const placements = [
      NormalizedSignaturePlacement(
          pageIndex: 0, x: .1, y: .7, width: .3, height: .1),
      NormalizedSignaturePlacement(
          pageIndex: 2, x: .5, y: .7, width: .3, height: .1),
    ];
    expect(DocumentSignatureService.placementsForPage(placements, 0),
        hasLength(1));
    expect(DocumentSignatureService.placementsForPage(placements, 1), isEmpty);
    expect(DocumentSignatureService.placementsForPage(placements, 2),
        hasLength(1));
  });

  test('transparent PNG alpha channel is retained in the source asset', () {
    final signature = _png(80, 30, transparent: true);
    final decoded = img.decodePng(signature)!;
    expect(decoded.getPixel(0, 0).a.toInt(), 0);
    expect(decoded.getPixel(10, 10).a.toInt(), greaterThan(0));
  });
}
