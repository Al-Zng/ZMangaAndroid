import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;
  NetworkMonitor._internal();

  final Connectivity _connectivity = Connectivity();
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _controller.stream;

  NetworkMonitor() {
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final connected = results.isNotEmpty && results.first != ConnectivityResult.none;
      if (connected != _isConnected) {
        _isConnected = connected;
        _controller.add(connected);
      }
    });
  }

  void dispose() {
    _controller.close();
  }
}