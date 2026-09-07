import 'package:flutter_test/flutter_test.dart';
import 'package:toursplit/core/utils/math_expression_evaluator.dart';

void main() {
  group('MathExpressionEvaluator Tests', () {
    test('Basic multiplication: 500 * 10', () {
      final res = MathExpressionEvaluator.tryEvaluate('500 * 10');
      expect(res, 5000.0);
      expect(MathExpressionEvaluator.formatResult(res!), '5000');
    });

    test('Parenthesized expression: (50 * 5) + 34 + 3489', () {
      final res = MathExpressionEvaluator.tryEvaluate('(50 * 5) + 34 + 3489');
      expect(res, 3773.0);
      expect(MathExpressionEvaluator.formatResult(res!), '3773');
    });

    test('Alternate symbols: ×, ÷, x, X', () {
      expect(MathExpressionEvaluator.tryEvaluate('50 × 10'), 500.0);
      expect(MathExpressionEvaluator.tryEvaluate('100 ÷ 4'), 25.0);
      expect(MathExpressionEvaluator.tryEvaluate('25 x 4'), 100.0);
      expect(MathExpressionEvaluator.tryEvaluate('20 X 5'), 100.0);
    });

    test('Decimals & precedence: 10 + 20 * 3.5 - 5 / 2', () {
      // 10 + 70 - 2.5 = 77.5
      final res = MathExpressionEvaluator.tryEvaluate('10 + 20 * 3.5 - 5 / 2');
      expect(res, 77.5);
      expect(MathExpressionEvaluator.formatResult(res!), '77.5');
    });

    test('Nested parentheses: ((10 + 5) * 2) - (4 / 2)', () {
      // 30 - 2 = 28
      final res = MathExpressionEvaluator.tryEvaluate('((10 + 5) * 2) - (4 / 2)');
      expect(res, 28.0);
    });

    test('Unary negative numbers: -50 + 100', () {
      expect(MathExpressionEvaluator.tryEvaluate('-50 + 100'), 50.0);
      expect(MathExpressionEvaluator.tryEvaluate('50 + (-10)'), 40.0);
    });

    test('Handles commas and spaces: ( 1,000 * 2 ) + 500', () {
      expect(MathExpressionEvaluator.tryEvaluate('( 1,000 * 2 ) + 500'), 2500.0);
    });

    test('Single plain number evaluates correctly', () {
      expect(MathExpressionEvaluator.tryEvaluate('1250'), 1250.0);
      expect(MathExpressionEvaluator.tryEvaluate('45.75'), 45.75);
    });

    test('Detects math operators: hasMathOperators', () {
      expect(MathExpressionEvaluator.hasMathOperators('500 * 10'), isTrue);
      expect(MathExpressionEvaluator.hasMathOperators('(50 + 2)'), isTrue);
      expect(MathExpressionEvaluator.hasMathOperators('1500'), isFalse);
      expect(MathExpressionEvaluator.hasMathOperators('1500.50'), isFalse);
    });

    test('Safely handles invalid expressions without crashing', () {
      expect(MathExpressionEvaluator.tryEvaluate(''), isNull);
      expect(MathExpressionEvaluator.tryEvaluate('   '), isNull);
      expect(MathExpressionEvaluator.tryEvaluate('500 * '), isNull);
      expect(MathExpressionEvaluator.tryEvaluate('(500 + 10'), isNull);
      expect(MathExpressionEvaluator.tryEvaluate('500 / 0'), isNull);
      expect(MathExpressionEvaluator.tryEvaluate('abc + 123'), isNull);
      expect(MathExpressionEvaluator.tryEvaluate('++'), isNull);
    });
  });
}
