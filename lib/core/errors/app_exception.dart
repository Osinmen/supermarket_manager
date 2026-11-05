sealed class AppException implements Exception{ 
  const AppException(this.message);

  final String message;
  @override 
  String toString() => message;
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}

//something that must be uniques exsits already.
class DuplicateException extends AppException {
  const DuplicateException(super.message);
}
//the things being loked up does not exist

class NotFoundException extends AppException {
  const NotFoundException(super.message);
}
  //wrong user name of pasword or an inactive account
class AuthException extends AppException {
  const AuthException(super.message);
}
//the signed in user does not allow this action
class PermissionDeniedException extends AppException {
  const PermissionDeniedException(super.message);
}