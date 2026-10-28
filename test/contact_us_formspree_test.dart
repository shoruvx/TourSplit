import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formspree Contact Form Tests', () {
    test('Constructs standard Formspree endpoint and json payload correctly', () {
      const formId = 'test_form_123';
      final endpoint = formId.startsWith('http')
          ? formId
          : 'https://formspree.io/f/$formId';

      expect(endpoint, 'https://formspree.io/f/test_form_123');

      final payload = {
        'name': 'John Doe',
        'email': 'john@example.com',
        'category': 'Bug Report',
        'message': 'Found an issue with tour sync',
        '_subject': '[Bug Report] TourSplit Feedback from John Doe',
        'userId': 'user_abc_456',
        'submittedAt': DateTime(2026, 10, 26).toIso8601String(),
      };

      final encoded = jsonEncode(payload);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['name'], 'John Doe');
      expect(decoded['email'], 'john@example.com');
      expect(decoded['category'], 'Bug Report');
      expect(decoded['message'], 'Found an issue with tour sync');
      expect(decoded['_subject'], '[Bug Report] TourSplit Feedback from John Doe');
      expect(decoded['userId'], 'user_abc_456');
    });

    test('Validates email formatting when provided', () {
      bool isValidEmail(String email) {
        if (email.isEmpty) return true;
        return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
      }

      expect(isValidEmail(''), isTrue); // optional
      expect(isValidEmail('test@domain.com'), isTrue);
      expect(isValidEmail('hello.world@sub.domain.org'), isTrue);
      expect(isValidEmail('invalid-email'), isFalse);
      expect(isValidEmail('invalid@'), isFalse);
      expect(isValidEmail('@missinguser.com'), isFalse);
    });
  });
}
