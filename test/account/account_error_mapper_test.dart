import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_error_mapper.dart';

void main() {
  test('exposes the exact neutral recovery acknowledgement', () {
    expect(
      AccountErrorMapper.recoveryAcceptedMessage,
      'หากอีเมลนี้มีบัญชี เราได้ส่งลิงก์ตั้งรหัสผ่านใหม่แล้ว',
    );
  });

  test('maps credential failures to one non-enumerating sign-in message', () {
    for (final code in [
      'user-not-found',
      'wrong-password',
      'invalid-credential',
    ]) {
      expect(
        AccountErrorMapper.messageFor(code),
        'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
      );
    }
  });

  test('maps account operation errors to safe Thai messages', () {
    expect(
      AccountErrorMapper.messageFor('network-request-failed'),
      'ไม่สามารถเชื่อมต่อเครือข่ายได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต',
    );
    expect(
      AccountErrorMapper.messageFor('too-many-requests'),
      'มีการพยายามทำรายการมากเกินไป กรุณาลองใหม่ภายหลัง',
    );
    expect(
      AccountErrorMapper.messageFor('user-disabled'),
      'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแลระบบ',
    );
    expect(
      AccountErrorMapper.messageFor('weak-password'),
      'รหัสผ่านไม่ปลอดภัย ต้องมีอย่างน้อย 8 ตัวอักษร และมีทั้งตัวอักษรและตัวเลข',
    );
    expect(
      AccountErrorMapper.messageFor('requires-recent-login'),
      'เพื่อความปลอดภัย กรุณาเข้าสู่ระบบใหม่ก่อนดำเนินการ',
    );
    expect(
      AccountErrorMapper.messageFor('invalid-action-code'),
      'ลิงก์นี้ไม่ถูกต้องหรือถูกใช้งานไปแล้ว กรุณาขอลิงก์ใหม่',
    );
    expect(
      AccountErrorMapper.messageFor('expired-action-code'),
      'ลิงก์นี้หมดอายุแล้ว กรุณาขอลิงก์ใหม่',
    );
    expect(
      AccountErrorMapper.messageFor('credential-already-in-use'),
      'ข้อมูลการเข้าสู่ระบบนี้ถูกใช้งานกับบัญชีอื่นแล้ว',
    );
  });

  test('uses a generic fallback that cannot expose provider details', () {
    expect(
      AccountErrorMapper.messageFor('backend-error: sensitive detail'),
      'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
    );
  });
}
