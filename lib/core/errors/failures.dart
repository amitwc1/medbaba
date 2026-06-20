/// Base failure class for the app
abstract class Failure {
  final String message;
  final int? code;

  const Failure({required this.message, this.code});

  @override
  String toString() => 'Failure(message: $message, code: $code)';
}

/// Server/network related failures
class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code});
}

/// Local cache/database failures
class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code});
}

/// Authentication failures
class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code});
}

/// Validation failures (input errors)
class ValidationFailure extends Failure {
  final Map<String, String>? fieldErrors;

  const ValidationFailure({
    required super.message,
    super.code,
    this.fieldErrors,
  });
}

/// Network connectivity failures
class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'No internet connection. Please check your network.',
  });
}

/// Firebase specific failures
class FirebaseFailure extends Failure {
  const FirebaseFailure({required super.message, super.code});
}

/// Permission failures
class PermissionFailure extends Failure {
  const PermissionFailure({
    super.message = 'Permission denied. Please grant the required permissions.',
  });
}

/// Not found failures
class NotFoundFailure extends Failure {
  const NotFoundFailure({super.message = 'The requested resource was not found.'});
}

/// Sync failures
class SyncFailure extends Failure {
  const SyncFailure({required super.message, super.code});
}

/// AI / Gemini failures
class AIFailure extends Failure {
  const AIFailure({required super.message, super.code});
}
