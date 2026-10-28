import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/firebase_account_gateway.dart'
    as firebase;

AccountGateway _asAccountGateway(firebase.FirebaseAccountGateway gateway) =>
    gateway;

void main() {
  test(
    'exposes a typed account operation failure without provider details',
    () {
      const failure = AccountOperationException('wrong-password');

      expect(failure.code, 'wrong-password');
      expect(failure.toString(), 'AccountOperationException(wrong-password)');
    },
  );

  test(
    'Firebase adapter is available through the account gateway contract',
    () {
      expect(_asAccountGateway, isA<Function>());
    },
  );
}
