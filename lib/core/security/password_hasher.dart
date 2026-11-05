import 'dart:convert';
import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';
abstract final class PasswordHasher{
  static const minLength = 8;

  //bcrypt only looks at the first 72 bytes of a password
  static const maxBytes = 72;

  //const factor: each +1 doubles the time. 12 is slow enough to frustrate
  //guessing and fast enough for a login

  static const _cost = 12;

  static String? validate(String password) {
    if(password.length < minLength) {
      return 'User at least $minLength characters';
    }
    if(utf8.encode(password).length > maxBytes) {
      return 'Use at most $maxBytes characters.';
    }
    return null;
  }
  static Future<bool> verify (String password, String hash) {
    return Isolate.run(() {
      try{
        return BCrypt.checkpw(password, hash);
      } catch(_) {
        //a malformed hash must never crash the login
        return false;
      }
    });
  }

}