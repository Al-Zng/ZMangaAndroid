import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class NetworkMonitor extends ChangeNotifier {
  static final NetworkMonitor shared = NetworkMonitor._();
  NetworkMonitor._();

  final Connectivity _connectivity = Connectivity();
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  StreamSubscription<ConnectivityResult>? _subscription;

  NetworkMonitor() {
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final connected = result != ConnectivityResult.none;
      if (connected != _isConnected) {
        _isConnected = connected;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}