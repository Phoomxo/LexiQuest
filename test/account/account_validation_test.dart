import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_validation.dart';

void main() {
  test('normalizes email and enforces one password policy', () {
    expect(
      AccountValidation.normalizeEmail(' Student@Example.COM '),
      'student@example.com',
    );
    expect(AccountValidation.passwordError('short'), isNotNull);
    expect(AccountValidation.passwordError('abcdefgh'), isNotNull);
    expect(AccountValidation.passwordError('12345678'), isNotNull);
    expect(AccountValidation.passwordError('learn123'), isNull);
    expect(AccountValidation.passwordError('ภาษาไทย123'), isNull);
    expect(AccountValidation.passwordError('ภาษาไทย๑๒๓'), isNull);
  });

  test('uses the documented Latin and Thai letter and digit policy', () {
    expect(AccountValidation.passwordError('กขคงจฉช๑'), isNull);
    expect(AccountValidation.passwordError('12345678×'), isNotNull);
    expect(AccountValidation.passwordError('12345678่'), isNotNull);
  });

  test('rejects invalid and blank email addresses', () {
    expect(AccountValidation.emailError(''), isNotNull);
    expect(AccountValidation.emailError('student.example.com'), isNotNull);
    expect(AccountValidation.emailError('student@example.com'), isNull);
  });

  test('requires password confirmation to match', () {
    expect(AccountValidation.confirmationError('learn123', ''), isNotNull);
    expect(
      AccountValidation.confirmationError('learn123', 'learn321'),
      isNotNull,
    );
    expect(AccountValidation.confirmationError('learn123', 'learn123'), isNull);
  });

  test('requires non-empty names through every name validator', () {
    expect(AccountValidation.nameError('  '), isNotNull);
    expect(AccountValidation.firstNameError('  '), isNotNull);
    expect(AccountValidation.lastNameError('  '), isNotNull);
    expect(AccountValidation.nameError('Phet'), isNull);
    expect(AccountValidation.firstNameError('Phet'), isNull);
    expect(AccountValidation.lastNameError('Thong'), isNull);
  });

  test('accepts only ages from six through one hundred twenty', () {
    expect(AccountValidation.ageError('5'), isNotNull);
    expect(AccountValidation.ageError(121), isNotNull);
    expect(AccountValidation.ageError('six'), isNotNull);
    expect(AccountValidation.ageError('6'), isNull);
    expect(AccountValidation.ageError(120), isNull);
  });
}
