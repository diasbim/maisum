import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService({
    Stream<List<ConnectivityResult>>? onConnectivityChanged,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    bool? initialOnline,
  })  : _overrideStream = onConnectivityChanged,
        _overrideCheck = checkConnectivity,
        _isOnline = initialOnline ?? true {
    _init();
  }

  final _connectivity = Connectivity();
  final Stream<List<ConnectivityResult>>? _overrideStream;
  final Future<List<ConnectivityResult>> Function()? _overrideCheck;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _isOnline;
  bool _disposed = false;
  bool get isOnline => _isOnline;

  Stream<bool> get onConnectivityChanged => _controller.stream;

  void _init() {
    final stream = _overrideStream ?? _connectivity.onConnectivityChanged;
    _connectivitySub = stream.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        _emit(_isOnline);
      }
    });

    _checkInitial();
  }

  Future<void> _checkInitial() async {
    final results = _overrideCheck != null
        ? await _overrideCheck!()
        : await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    _emit(_isOnline);
  }

  Future<bool> check() async {
    final results = _overrideCheck != null
        ? await _overrideCheck!()
        : await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    return _isOnline;
  }

  void _emit(bool isOnline) {
    if (_disposed || _controller.isClosed) return;
    _controller.add(isOnline);
  }

  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    _controller.close();
  }
}
