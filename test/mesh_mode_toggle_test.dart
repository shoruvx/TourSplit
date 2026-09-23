import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/presentation/chat/widgets/mesh_mode_toggle.dart';

void main() {
  group('MeshModeToggle Widget Tests', () {
    testWidgets('renders Internet mode when isMeshActive is false', (tester) async {
      bool toggledValue = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MeshModeToggle(
                isMeshActive: false,
                onToggle: (val) => toggledValue = val,
              ),
            ),
          ),
        ),
      );

      // Verify text inside slider shows Internet
      expect(find.text('Internet'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);

      // Verify icons are present
      expect(find.byIcon(Icons.wifi_rounded), findsWidgets);
      expect(find.byIcon(Icons.wifi_off_rounded), findsWidgets);

      // Tap toggle to trigger switch to Offline mode
      await tester.tap(find.byType(MeshModeToggle));
      await tester.pumpAndSettle();

      expect(toggledValue, isTrue);
    });

    testWidgets('renders Offline mode when isMeshActive is true', (tester) async {
      bool toggledValue = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MeshModeToggle(
                isMeshActive: true,
                peerCount: 3,
                onToggle: (val) => toggledValue = val,
              ),
            ),
          ),
        ),
      );

      // Verify text inside slider shows Offline
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Internet'), findsNothing);

      // Verify icons are present
      expect(find.byIcon(Icons.wifi_off_rounded), findsWidgets);
      expect(find.byIcon(Icons.wifi_rounded), findsWidgets);

      // Tap toggle to trigger switch back to Internet mode
      await tester.tap(find.byType(MeshModeToggle));
      await tester.pumpAndSettle();

      expect(toggledValue, isFalse);
    });

    testWidgets('tapping left side switches to Internet and right side switches to Offline', (tester) async {
      bool? lastToggled;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MeshModeToggle(
                isMeshActive: false,
                onToggle: (val) => lastToggled = val,
              ),
            ),
          ),
        ),
      );

      // Tap on the right side of the toggle (Offline side)
      final toggleFinder = find.byType(MeshModeToggle);
      final center = tester.getCenter(toggleFinder);
      await tester.tapAt(center + const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(lastToggled, isTrue);
    });
  });
}
