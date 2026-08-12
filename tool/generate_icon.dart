// Generates the Android launcher icons from the master logo.
//
//   dart run tool/generate_icon.dart
//
// Re-run after changing assets/branding/kopi-kompas-logo.png.
//
// Two things about the master constrain everything here. The wordmark
// occupies the bottom third and is illegible at 48 dp, so only the compass
// mark is used — and cropping it also drops the stray superscript "R" above
// "Kompas", which is a generation artifact rather than a trademark claim. And
// the adaptive foreground must sit inside the safe zone (the centre 66 of 108
// units) or the system mask clips a point off the star.
//
// The master is build-time input and never ships: it is deliberately absent
// from pubspec.yaml, and test/icon_test.dart fails if it reappears.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';

/// The compass mark's extent within the master, measured from the artwork.
const _markLeft = 0.21;
const _markRight = 0.79;
const _markTop = 0.16;
const _markBottom = 0.71;

/// Tan from the logo, used as the legacy icon ground and the adaptive
/// background colour.
final _tan = ColorRgb8(0xDD, 0xBC, 0x8E);

const _densities = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

void main() {
  final master = File('assets/branding/kopi-kompas-logo.png');
  if (!master.existsSync()) {
    stderr.writeln('missing ${master.path}');
    exit(1);
  }

  final source = decodePng(master.readAsBytesSync());
  if (source == null) {
    stderr.writeln('could not decode ${master.path}');
    exit(1);
  }

  final mark = copyCrop(
    source,
    x: (source.width * _markLeft).round(),
    y: (source.height * _markTop).round(),
    width: (source.width * (_markRight - _markLeft)).round(),
    height: (source.height * (_markBottom - _markTop)).round(),
  );

  final cutout = _keyOutBackground(mark);

  _densities.forEach((density, size) {
    final dir = Directory('android/app/src/main/res/mipmap-$density')
      ..createSync(recursive: true);

    // Legacy icon: the mark on the tan ground, filling most of the square.
    File(
      '${dir.path}/ic_launcher.png',
    ).writeAsBytesSync(encodePng(_fit(mark, size, 0.92, _tan)));

    // Adaptive foreground: a 108dp canvas with the mark inside the 66dp
    // safe zone, on transparency so the background layer shows through.
    File('${dir.path}/ic_launcher_foreground.png').writeAsBytesSync(
      encodePng(_fit(cutout, (size * 108 / 48).round(), 66 / 108, null)),
    );
  });

  Directory(
    'android/app/src/main/res/mipmap-anydpi-v26',
  ).createSync(recursive: true);
  File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
      .writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');

  Directory('android/app/src/main/res/values').createSync(recursive: true);
  File('android/app/src/main/res/values/ic_launcher_background.xml')
      .writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#DDBC8E</color>
</resources>
''');

  stdout.writeln('wrote ${_densities.length} densities + adaptive icon');
}

/// Replaces the master's flat tan ground with transparency.
///
/// The master is RGB with no alpha, so a straight crop carries its background
/// along. An opaque foreground still *composites* correctly — the background
/// layer is the same tan — but launchers that parallax the foreground would
/// slide a visible tan square across the icon.
///
/// A global colour key is safe here rather than a flood fill: the ground is
/// one flat tone and every bean is far darker, so nothing inside the mark
/// comes near the threshold. Alpha ramps across the last quarter of the
/// tolerance so the bean edges stay smooth instead of aliasing.
Image _keyOutBackground(Image src) {
  final out = src.convert(numChannels: 4);
  final bg = out.getPixel(1, 1); // a corner: always ground, never mark
  const tolerance = 42.0;
  const soft = tolerance * 0.75;

  for (final p in out) {
    final d = _distance(p.r, p.g, p.b, bg.r, bg.g, bg.b);
    if (d <= soft) {
      p.a = 0;
    } else if (d < tolerance) {
      p.a = (255 * (d - soft) / (tolerance - soft)).round();
    }
  }
  return out;
}

double _distance(num r1, num g1, num b1, num r2, num g2, num b2) {
  final dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
  return sqrt(dr * dr + dg * dg + db * db);
}

/// Scales [mark] to occupy [fraction] of a [size]-square canvas, centred.
///
/// [background] null leaves the canvas transparent, which the adaptive
/// foreground needs so the background layer shows through.
Image _fit(Image mark, int size, double fraction, Color? background) {
  final canvas = Image(width: size, height: size, numChannels: 4);
  if (background != null) {
    fill(canvas, color: background);
  } else {
    fill(canvas, color: ColorRgba8(0, 0, 0, 0));
  }

  final target = (size * fraction).round();
  final scaled = copyResize(
    mark,
    width: mark.width >= mark.height ? target : null,
    height: mark.width >= mark.height ? null : target,
    interpolation: Interpolation.cubic,
  );

  compositeImage(
    canvas,
    scaled,
    dstX: ((size - scaled.width) / 2).round(),
    dstY: ((size - scaled.height) / 2).round(),
  );
  return canvas;
}
