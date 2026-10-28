final class AccountErrorMapper {
  AccountErrorMapper._();

  static const recoveryAcceptedMessage =
      'หากอีเมลนี้มีบัญชี เราได้ส่งลิงก์ตั้งรหัสผ่านใหม่แล้ว';

  static String messageFor(String code) => switch (code) {
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
    'network-request-failed' =>
      'ไม่สามารถเชื่อมต่อเครือข่ายได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต',
    'too-many-requests' => 'มีการพยายามทำรายการมากเกินไป กรุณาลองใหม่ภายหลัง',
    'user-disabled' => 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแลระบบ',
    'weak-password' =>
      'รหัสผ่านไม่ปลอดภัย ต้องมีอย่างน้อย 8 ตัวอักษร และมีทั้งตัวอักษรและตัวเลข',
    'requires-recent-login' =>
      'เพื่อความปลอดภัย กรุณาเข้าสู่ระบบใหม่ก่อนดำเนินการ',
    'invalid-action-code' =>
      'ลิงก์นี้ไม่ถูกต้องหรือถูกใช้งานไปแล้ว กรุณาขอลิงก์ใหม่',
    'expired-action-code' => 'ลิงก์นี้หมดอายุแล้ว กรุณาขอลิงก์ใหม่',
    'credential-already-in-use' || 'email-already-in-use' =>
      'ข้อมูลการเข้าสู่ระบบนี้ถูกใช้งานกับบัญชีอื่นแล้ว',
    _ => 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
  };
}
