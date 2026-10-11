import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_guide.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/data/guide_photo.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/entry_detail_screen.dart';
import 'package:kopi_kompas/screens/full_log_screen.dart';
import 'package:kopi_kompas/screens/home_screen.dart';
import 'package:kopi_kompas/services/brew_database.dart';
import 'package:kopi_kompas/services/kopi_client.dart';
import 'package:kopi_kompas/services/reminder_service.dart';
import 'package:kopi_kompas/services/settings_store.dart';
import 'package:kopi_kompas/strings.dart';
import 'package:kopi_kompas/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Notifications implements Notifications {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> scheduleAt(DateTime when, String title, String body) async {}
}

void main() {
  late BrewSchema schema;
  late BrewGuides guides;
  late GuidePhotos photos;
  late BrewDatabase db;
  late HttpClient http;

  setUpAll(() async {
    final fontDirectory = Platform.environment['KOPI_QA_FONTS'];
    if (fontDirectory != null) {
      for (final font in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(font.key);
        loader.addFont(
          File(
            '$fontDirectory/${font.value}',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      }
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    guides = BrewGuides.parse(File('assets/guides.json').readAsStringSync());
    photos = GuidePhotos.parse(
      File('assets/guide_credits.json').readAsStringSync(),
    );
  });
  setUp(() async {
    AppStrings.language = 'en';
    SharedPreferences.setMockInitialValues({'reminder.enabled': false});
    db = await BrewDatabase.open(path: inMemoryDatabasePath);
    http = HttpClient();
  });
  tearDown(() async {
    http.close(force: true);
    await db.close();
    AppStrings.language = 'en';
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    String method = 'espresso',
    GuidePhotos? catalog,
    Brightness brightness = Brightness.light,
    String language = 'en',
  }) async {
    AppStrings.language = language;
    await tester.runAsync(
      () => db.insert(
        BrewEntry(
          id: 'photo-brew',
          brewMethod: method,
          brewDate: DateTime(2026, 10, 11, 7),
          rawInputText: 'Test brew: 15g dose, 25g yield, 30 seconds.',
          doseGrams: 15,
          methodData: const {
            'shotStyle': 'normale',
            'yieldGrams': 25,
            'brewTimeSeconds': 30,
          },
          scoreStatus: ScoreStatus.scored,
          overallScore: 85,
          scoreRubric: 'r3',
          scoreModel: 'test-model',
          createdAt: DateTime(2026, 10, 11, 7),
          updatedAt: DateTime(2026, 10, 11, 7),
        ),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('photo-review'),
        child: MaterialApp(
          theme: kopiTheme(brightness).copyWith(
            textTheme: Platform.environment['KOPI_QA_FONTS'] == null
                ? null
                : kopiTheme(brightness).textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: HomeScreen(
            db: db,
            schema: schema,
            client: KopiClient(
              endpoint: 'https://example.invalid',
              installId: 'photo-test',
              http: http,
            ),
            reminder: ReminderService(
              db: db,
              settings: SettingsStore(),
              notifications: _Notifications(),
            ),
            guides: guides,
            photos: catalog ?? photos,
            auth: null,
            backup: null,
          ),
        ),
      ),
    );
    await tester.runAsync(() => db.liveEntries());
    await tester.pumpAndSettle();
  }

  Finder espressoImage() => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == 'assets/guides/espresso.jpg',
  );

  testWidgets('home log shows the method photo with its author and licence', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(espressoImage(), findsOneWidget);
    expect(find.text('Schill · CC BY 2.0'), findsOneWidget);
    expect(tester.widget<Image>(espressoImage()).fit, BoxFit.contain);
    expect(tester.getSize(espressoImage()).width, lessThanOrEqualTo(80));
  });

  testWidgets('opening a brew carries its photo and credit into details', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Espresso'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryDetailScreen), findsOneWidget);
    expect(espressoImage(), findsOneWidget);
    expect(find.text('Schill · CC BY 2.0'), findsOneWidget);
    expect(tester.widget<Image>(espressoImage()).fit, BoxFit.contain);
    expect(tester.getSize(espressoImage()).height, lessThanOrEqualTo(240));
  });

  testWidgets('full log receives the same photo catalog from home', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip(AppStrings.fullLogTitle));
    await tester.pump();
    await tester.runAsync(() => db.liveEntries());
    await tester.pumpAndSettle();
    expect(find.byType(FullLogScreen), findsOneWidget);
    expect(espressoImage(), findsOneWidget);
    expect(find.text('Schill · CC BY 2.0'), findsOneWidget);
    expect(tester.widget<Image>(espressoImage()).fit, BoxFit.contain);
  });

  testWidgets('a method without a licensed photo remains readable', (
    tester,
  ) async {
    await pumpHome(tester, method: 'kopiTalua');
    expect(find.byType(Image), findsNothing);
    expect(find.text(schema.method('kopiTalua').label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a brew remains reachable with keyboard navigation', (
    tester,
  ) async {
    await pumpHome(tester);
    var focused = false;
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final context = FocusManager.instance.primaryFocus?.context;
      if (context?.findAncestorWidgetOfExactType<ListTile>() != null) {
        focused = true;
        break;
      }
    }
    expect(focused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(EntryDetailScreen), findsOneWidget);
    expect(espressoImage(), findsOneWidget);
  });

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['KOPI_PHOTO_QA'];
    if (directory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('photo-review')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final language in ['en', 'id']) {
      testWidgets(
        'log photo fits phone with large $language text, $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpHome(tester, brightness: brightness, language: language);
          expect(espressoImage(), findsOneWidget);
          expect(find.text('Schill · CC BY 2.0'), findsOneWidget);
          final bounds = tester.getRect(espressoImage());
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(360));
          expect(tester.takeException(), isNull);
          await capture(tester, 'home-$language-${brightness.name}');
          await tester.tap(find.byTooltip(AppStrings.fullLogTitle));
          await tester.pump();
          await tester.runAsync(() => db.liveEntries());
          await tester.pumpAndSettle();
          expect(espressoImage(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture(tester, 'archive-$language-${brightness.name}');
          await tester.pageBack();
          await tester.pump();
          await tester.runAsync(() async {
            await db.liveEntries();
            await db.hasBrewOn(DateTime.now());
          });
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, 'Espresso'));
          await tester.pumpAndSettle();
          expect(espressoImage(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture(tester, 'details-$language-${brightness.name}');
        },
      );
    }
  }

  test('photo credits meet small-text contrast in both themes', () {
    for (final brightness in Brightness.values) {
      final theme = kopiTheme(brightness);
      final ink = theme.colorScheme.onSurface.computeLuminance();
      final paper = theme.scaffoldBackgroundColor.computeLuminance();
      final ratio =
          ((ink > paper ? ink : paper) + 0.05) /
          ((ink < paper ? ink : paper) + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));
      if (Platform.environment['KOPI_PHOTO_QA'] != null) {
        debugPrint('Photo credit contrast ${brightness.name}: $ratio:1');
      }
    }
  });
}
