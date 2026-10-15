import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/presentation/widgets/first_time_guide_dialog.dart';

void main() {
  group('Welcome Guide Screen Feature Tests', () {
    test('contains all 6 core tour features', () {
      expect(FirstTimeGuideDialog.features.length, 6);

      // 1. Create/join tour with QR
      expect(
        FirstTimeGuideDialog.features[0].title,
        'Create & Join Tours with QR',
      );
      expect(FirstTimeGuideDialog.features[0].badge, 'QR & Code');

      // 2. Add members with code or qr code
      expect(
        FirstTimeGuideDialog.features[1].title,
        'Add Members with Code or QR',
      );
      expect(FirstTimeGuideDialog.features[1].badge, 'Easy Invites');

      // 3. Add expense, split custom/equally
      expect(
        FirstTimeGuideDialog.features[2].title,
        'Add Expenses & Split Custom / Equally',
      );
      expect(FirstTimeGuideDialog.features[2].badge, 'Flexible Split');

      // 4. See balance sheet
      expect(
        FirstTimeGuideDialog.features[3].title,
        'Live Transparent Balance Sheet',
      );
      expect(FirstTimeGuideDialog.features[3].badge, 'Balance Sheet');

      // 5. Chat with team members in both online and offline
      expect(
        FirstTimeGuideDialog.features[4].title,
        'Chat in Both Online & Offline',
      );
      expect(FirstTimeGuideDialog.features[4].badge, 'Online & Mesh');

      // 6. Export all the chat history and settle every amounts effortlessly
      expect(
        FirstTimeGuideDialog.features[5].title,
        'Export Chat & Settle Effortlessly',
      );
      expect(FirstTimeGuideDialog.features[5].badge, '1-Tap Settle');
    });

    testWidgets('renders redesigned welcome guide screen correctly',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FirstTimeGuideDialog(),
        ),
      );
      // Let entrance animations settle so timers finish
      await tester.pumpAndSettle();

      // Header verification
      expect(find.text('WELCOME GUIDE'), findsOneWidget);
      expect(find.text('Split Costs, Keep Memories'), findsOneWidget);
      expect(find.text('Got It & Explore'), findsOneWidget);

      // Feature title verification
      expect(find.text('Create & Join Tours with QR'), findsOneWidget);
      expect(find.text('Add Members with Code or QR'), findsOneWidget);
      expect(find.text('Add Expenses & Split Custom / Equally'), findsOneWidget);
      expect(find.text('Live Transparent Balance Sheet'), findsOneWidget);
      expect(find.text('Chat in Both Online & Offline'), findsOneWidget);
      expect(find.text('Export Chat & Settle Effortlessly'), findsOneWidget);
    });
  });
}
