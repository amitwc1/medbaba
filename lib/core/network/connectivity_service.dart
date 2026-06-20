import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  ConnectivityService._() {
    _connectivity.onConnectivityChanged.listen((results) {
      final online = _isAnyResultConnected(results);
      _controller.add(online);
    });
  }

  Future<void> initialize() async {
    // Initialization is handled in the constructor
  }

  Stream<bool> get onConnectivityChanged => _controller.stream;

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return _isAnyResultConnected(result);
  }

  bool _isAnyResultConnected(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((result) => result != ConnectivityResult.none);
  }

  void dispose() {
    _controller.close();
  }
}
