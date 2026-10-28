import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_models.dart';

void main() {
  test('parses only the configured reset-password action link', () {
    final action = AccountActionLink.tryParse(
      Uri.parse(
        'https://vocab-learning-app-219ef.web.app/auth/action'
        '?mode=resetPassword&oobCode=one-time-code',
      ),
    );

    expect(
      action,
      const AccountActionLink(
        mode: AccountActionMode.resetPassword,
        code: 'one-time-code',
      ),
    );
  });

  test('rejects foreign hosts, paths, modes, and missing codes', () {
    expect(
      AccountActionLink.tryParse(
        Uri.parse(
          'https://evil.example/auth/action?mode=resetPassword&oobCode=x',
        ),
      ),
      isNull,
    );
    expect(
      AccountActionLink.tryParse(
        Uri.parse(
          'https://vocab-learning-app-219ef.web.app/other'
          '?mode=resetPassword&oobCode=x',
        ),
      ),
      isNull,
    );
    expect(
      AccountActionLink.tryParse(
        Uri.parse(
          'https://vocab-learning-app-219ef.web.app/auth/action'
          '?mode=resetPassword',
        ),
      ),
      isNull,
    );
    expect(
      AccountActionLink.tryParse(
        Uri.parse(
          'https://vocab-learning-app-219ef.web.app/auth/action'
          '?mode=recoverEmail&oobCode=x',
        ),
      ),
      isNull,
    );
  });
}
