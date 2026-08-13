import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/guide_photo.dart';
import 'package:kopi_kompas/widgets/guide_photo_card.dart';

late GuidePhotos photos;

void main() {
  setUpAll(() {
    photos = GuidePhotos.parse(
      File('assets/guide_credits.json').readAsStringSync(),
    );
  });

  testWidgets('a photo is never cropped to fit a box', (tester) async {
    // The photographs were taken by thirteen different people and run from
    // 0.67 to 1.78. BoxFit.cover with a fixed height showed the middle third
    // of every portrait, which on a French press was a picture of a jug's
    // waist. Nothing here may reintroduce that.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GuidePhotoCard(photo: photos.all.first)),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.height, isNull, reason: 'a fixed height forces a crop');
  });

  testWidgets('a tall photo is bounded rather than left to eat the screen', (
    tester,
  ) async {
    final tall = photos.forMethod('aeropress')!; // 720x1080
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GuidePhotoCard(photo: tall, maxHeight: 200)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Image)).height, lessThanOrEqualTo(200));
  });

  testWidgets('the credit travels with the image', (tester) async {
    // Attribution is a licence condition. There must be no way to render the
    // photograph without the author and licence beside it.
    final p = photos.all.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GuidePhotoCard(photo: p)),
      ),
    );
    expect(find.text(p.shortCredit), findsOneWidget);
  });
}
