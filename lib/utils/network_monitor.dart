import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class NetworkMonitor extends ChangeNotifier {
  static final NetworkMonitor shared = NetworkMonitor._internal();
  NetworkMonitor._internal() {
    _init();
  }

  final Connectivity _connectivity = Connectivity();
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  StreamSubscription<ConnectivityResult>? _subscription;

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final connected = result != ConnectivityResult.none;
      if (connected != _isConnected) {
        _isConnected = connected;
        notifyListeners();
      }
    });

    _connectivity.checkConnectivity().then((result) {
      _isConnected = result != ConnectivityResult.none;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
