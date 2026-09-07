/// A safe, zero-dependency recursive-descent mathematical expression evaluator.
/// Supports:
/// - Basic arithmetic: +, -, *, /, ×, ÷, x, X
/// - Parentheses / brackets: (, )
/// - Operator precedence (* and / evaluated before + and -)
/// - Decimals (e.g. 50.5, 3489.25)
/// - Unary signs (+5, -10)
/// - Handles spaces and commas gracefully
/// - Safe error handling: returns null on invalid syntax or division by zero.
class MathExpressionEvaluator {
  /// Evaluates an arithmetic expression string like "500 * 10" or "(50 * 5) + 34 + 3489".
  /// Returns the computed [double], or `null` if the expression is invalid or empty.
  static double? tryEvaluate(String expression) {
    final sanitized = _sanitize(expression);
    if (sanitized.isEmpty) return null;

    try {
      final tokens = _tokenize(sanitized);
      if (tokens.isEmpty) return null;

      final parser = _Parser(tokens);
      final result = parser.parseExpression();

      // Ensure all tokens were consumed
      if (parser.hasMoreTokens()) {
        return null;
      }

      if (result.isNaN || result.isInfinite) {
        return null;
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if the string contains any arithmetic operator or bracket.
  static bool hasMathOperators(String input) {
    return input.contains(RegExp(r'[\+\-\*\/\(\)\×\÷xX]'));
  }

  /// Formats the result as a clean string:
  /// - Whole numbers without decimal places (e.g. 5000.0 -> "5000")
  /// - Decimals with up to 2 decimal places (e.g. 50.25 -> "50.25", 12.5 -> "12.5")
  static String formatResult(double value) {
    if (value.isInfinite || value.isNaN) return '0';
    final rounded = (value * 100).round() / 100;
    if (rounded % 1 == 0) {
      return rounded.toInt().toString();
    } else {
      // Remove trailing zero if applicable (e.g. 12.50 -> 12.5)
      final str = rounded.toStringAsFixed(2);
      if (str.endsWith('0')) {
        return str.substring(0, str.length - 1);
      }
      return str;
    }
  }

  static String _sanitize(String input) {
    return input
        .replaceAll(',', '')
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('x', '*')
        .replaceAll('X', '*')
        .replaceAll(' ', '')
        .trim();
  }

  static List<_Token> _tokenize(String s) {
    final tokens = <_Token>[];
    int i = 0;

    while (i < s.length) {
      final c = s[i];

      if (c == '+' || c == '-' || c == '*' || c == '/' || c == '(' || c == ')') {
        tokens.add(_Token(_TokenType.operatorOrParen, c));
        i++;
      } else if (_isDigit(c) || c == '.') {
        final start = i;
        bool hasDot = c == '.';
        i++;
        while (i < s.length && (_isDigit(s[i]) || (!hasDot && s[i] == '.'))) {
          if (s[i] == '.') hasDot = true;
          i++;
        }
        final numStr = s.substring(start, i);
        if (numStr == '.') return []; // standalone dot is invalid
        tokens.add(_Token(_TokenType.number, numStr));
      } else {
        // Unknown character -> invalid
        return [];
      }
    }

    return tokens;
  }

  static bool _isDigit(String s) {
    final code = s.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }
}

enum _TokenType { number, operatorOrParen }

class _Token {
  final _TokenType type;
  final String value;
  _Token(this.type, this.value);

  @override
  String toString() => value;
}

/// Grammar:
/// Expression -> Term (('+' | '-') Term)*
/// Term       -> Factor (('*' | '/') Factor)*
/// Factor     -> ('+' | '-') Factor | Primary
/// Primary    -> Number | '(' Expression ')'
class _Parser {
  final List<_Token> _tokens;
  int _pos = 0;

  _Parser(this._tokens);

  bool hasMoreTokens() => _pos < _tokens.length;

  _Token? _peek() => hasMoreTokens() ? _tokens[_pos] : null;

  _Token _consume() {
    if (!hasMoreTokens()) throw FormatException('Unexpected end of input');
    return _tokens[_pos++];
  }

  double parseExpression() {
    double value = _parseTerm();

    while (hasMoreTokens()) {
      final next = _peek();
      if (next != null && next.type == _TokenType.operatorOrParen && (next.value == '+' || next.value == '-')) {
        _consume();
        final right = _parseTerm();
        if (next.value == '+') {
          value += right;
        } else {
          value -= right;
        }
      } else {
        break;
      }
    }

    return value;
  }

  double _parseTerm() {
    double value = _parseFactor();

    while (hasMoreTokens()) {
      final next = _peek();
      if (next != null && next.type == _TokenType.operatorOrParen && (next.value == '*' || next.value == '/')) {
        _consume();
        final right = _parseFactor();
        if (next.value == '*') {
          value *= right;
        } else {
          if (right == 0) {
            throw FormatException('Division by zero');
          }
          value /= right;
        }
      } else {
        break;
      }
    }

    return value;
  }

  double _parseFactor() {
    final next = _peek();
    if (next != null && next.type == _TokenType.operatorOrParen) {
      if (next.value == '+') {
        _consume();
        return _parseFactor();
      } else if (next.value == '-') {
        _consume();
        return -_parseFactor();
      }
    }

    return _parsePrimary();
  }

  double _parsePrimary() {
    final token = _peek();
    if (token == null) {
      throw FormatException('Unexpected end of input');
    }

    if (token.type == _TokenType.number) {
      _consume();
      final numVal = double.tryParse(token.value);
      if (numVal == null) throw FormatException('Invalid number: ${token.value}');
      return numVal;
    }

    if (token.type == _TokenType.operatorOrParen && token.value == '(') {
      _consume(); // consume '('
      final val = parseExpression();
      final closing = _peek();
      if (closing == null || closing.value != ')') {
        throw FormatException('Missing closing parenthesis');
      }
      _consume(); // consume ')'
      return val;
    }

    throw FormatException('Unexpected token: ${token.value}');
  }
}
