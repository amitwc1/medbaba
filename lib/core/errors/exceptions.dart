/// Base exception class for the app
abstract class AppException implements Exception {
  final String message;
  final int? code;
  final dynamic originalError;

  const AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => '$runtimeType(message: $message, code: $code)';
}

/// Server/API exceptions
class ServerException extends AppException {
  const ServerException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Cache/database exceptions
class CacheException extends AppException {
  const CacheException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Authentication exceptions
class AuthException extends AppException {
  const AuthException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Network exceptions
class NetworkException extends AppException {
  const NetworkException({
    super.message = 'No internet connection',
    super.code,
    super.originalError,
  });
}

/// Firebase exceptions
class FirebaseAppException extends AppException {
  const FirebaseAppException({
    required super.message,
    super.code,
    super.originalError,
  });
}
