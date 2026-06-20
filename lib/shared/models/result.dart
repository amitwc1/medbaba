/// A discriminated union type for error handling.
/// Replaces try-catch with explicit success/failure types.
sealed class Result<T> {
  const Result();

  /// Create a successful result
  factory Result.success(T data) = Success<T>;

  /// Create a failure result
  factory Result.failure(String message, {int? code}) = ResultFailure<T>;

  /// Map the success value
  Result<R> map<R>(R Function(T data) transform) {
    return switch (this) {
      Success(data: final data) => Result.success(transform(data)),
      ResultFailure(message: final msg, code: final code) =>
        Result.failure(msg, code: code),
    };
  }

  /// Handle both cases
  R when<R>({
    required R Function(T data) success,
    required R Function(String message, int? code) failure,
  }) {
    return switch (this) {
      Success(data: final data) => success(data),
      ResultFailure(message: final msg, code: final code) =>
        failure(msg, code),
    };
  }

  /// Get data or null
  T? get dataOrNull => switch (this) {
        Success(data: final data) => data,
        ResultFailure() => null,
      };

  /// Check if success
  bool get isSuccess => this is Success<T>;

  /// Check if failure
  bool get isFailure => this is ResultFailure<T>;
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class ResultFailure<T> extends Result<T> {
  final String message;
  final int? code;
  const ResultFailure(this.message, {this.code});
}
