import 'package:flutter_test/flutter_test.dart';

String cleanPhoneDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}

bool isValidTenDigitPhone(String raw) {
  final digits = cleanPhoneDigits(raw);
  return digits.length == 10;
}

void main() {
  group('Phone Input Cleaning and Validation', () {
    test('cleans +91 formatted numbers', () {
      expect(cleanPhoneDigits('+91 98765 43210'), '9876543210');
      expect(isValidTenDigitPhone('+91 98765 43210'), isTrue);
    });

    test('cleans leading 0 numbers', () {
      expect(cleanPhoneDigits('09876543210'), '9876543210');
      expect(isValidTenDigitPhone('09876543210'), isTrue);
    });

    test('cleans standard 10 digit number with spaces or dashes', () {
      expect(cleanPhoneDigits('98765-43210'), '9876543210');
      expect(cleanPhoneDigits(' 98765 43210 '), '9876543210');
    });

    test('rejects numbers that are too short', () {
      expect(isValidTenDigitPhone('12345'), isFalse);
      expect(isValidTenDigitPhone(''), isFalse);
    });

    test('rejects numbers that are too long', () {
      expect(isValidTenDigitPhone('919876543210123'), isFalse);
    });
  });
}
