import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/presentation/widgets/whats_new_dialog.dart';
import 'package:toursplit/presentation/tour/widgets/tour_created_dialog.dart';

void main() {
  group('QR Code and URL Extraction Tests', () {
    String extractInviteCode(String input) {
      final clean = input.trim();

      // 1. Try parsing as a URL for 'code' or 'join' query parameter
      try {
        final uri = Uri.tryParse(clean);
        if (uri != null) {
          final codeParam =
              uri.queryParameters['code'] ?? uri.queryParameters['join'];
          if (codeParam != null && codeParam.trim().length == 6) {
            return codeParam.trim().toUpperCase();
          }
        }
      } catch (_) {}

      // 2. Look for code= or join= in raw string
      final queryMatch = RegExp(r'[?&](?:code|join)=([A-Z0-9]{6})\b',
              caseSensitive: false)
          .firstMatch(clean);
      if (queryMatch != null) {
        return queryMatch.group(1)!.toUpperCase();
      }

      // 3. Direct 6-character clean code
      final direct = clean.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
      if (direct.length == 6 && RegExp(r'^[A-Z0-9]{6}$').hasMatch(direct)) {
        return direct;
      }

      // 4. Word boundary match, excluding common URL keywords like GITHUB, LATEST
      final matches =
          RegExp(r'\b([A-Z0-9]{6})\b', caseSensitive: false).allMatches(clean);
      for (final m in matches) {
        final val = m.group(1)!.toUpperCase();
        if (val != 'GITHUB' && val != 'LATEST') {
          return val;
        }
      }

      return direct;
    }

    test('extracts direct 6-character code correctly', () {
      expect(extractInviteCode('ABC123'), 'ABC123');
      expect(extractInviteCode('  k9x2p4  '), 'K9X2P4');
      expect(extractInviteCode('xy-z7-89'), 'XYZ789');
    });

    test('extracts invite code from GitHub release URL with query param', () {
      const url =
          'https://github.com/shoruvx/TourSplit/releases/latest?code=K9X2P4';
      expect(extractInviteCode(url), 'K9X2P4');
    });

    test('extracts invite code from join URL with query param', () {
      const url = 'toursplit://join?code=XYZ789';
      expect(extractInviteCode(url), 'XYZ789');
    });

    test('ignores URL words like GITHUB or LATEST when searching for 6-char code',
        () {
      const raw =
          'https://github.com/shoruvx/TourSplit/releases/latest?join=M9P3T1';
      expect(extractInviteCode(raw), 'M9P3T1');
    });
  });

  group('WhatsNewDialog Features Tests', () {
    test('static features list contains the updated features', () {
      expect(WhatsNewDialog.features.length, 5);
      expect(WhatsNewDialog.features[0].title, 'Unified Bottom Navigation');
      expect(WhatsNewDialog.features[1].title, 'Expense Attribution Tracking');
      expect(WhatsNewDialog.features[2].title, 'Online & Offline Tour Chat');
      expect(WhatsNewDialog.features[3].title, 'Interactive Chat Reactions');
      expect(WhatsNewDialog.features[4].title, 'Offline Reliability & Sync');
    });
  });

  group('Date Day Stepper Logic Tests', () {
    test('Day number is calculated correctly across date steps', () {
      final startDate = DateTime(2026, 9, 1);
      final baseDate = DateTime(startDate.year, startDate.month, startDate.day);

      DateTime current = DateTime(2026, 9, 1);
      int calcDay(DateTime dt) {
        final expDate = DateTime(dt.year, dt.month, dt.day);
        final diff = expDate.difference(baseDate).inDays;
        return diff >= 0 ? diff + 1 : 1;
      }

      expect(calcDay(current), 1);

      // Step forward 1 day
      current = current.add(const Duration(days: 1));
      expect(calcDay(current), 2);

      // Step forward 3 days
      current = current.add(const Duration(days: 3));
      expect(calcDay(current), 5);

      // Step back 1 day
      current = current.subtract(const Duration(days: 1));
      expect(calcDay(current), 4);
    });
  });

  group('TourCreatedDialog Tests', () {
    testWidgets('renders TourCreatedDialog with tour name, code and triggers onDone',
        (tester) async {
      bool doneTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TourCreatedDialog(
              tourName: 'Sylhet Adventure',
              inviteCode: 'SYL789',
              onDone: () => doneTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Tour Created Successfully!'), findsOneWidget);
      expect(find.text('Sylhet Adventure'), findsOneWidget);
      expect(find.text('SYL789'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.ensureVisible(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(doneTapped, isTrue);
    });
  });
}
