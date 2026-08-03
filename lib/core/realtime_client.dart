import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:socket_io_client/socket_io_client.dart' as io;

enum RealtimeConnectionState { disconnected, connecting, connected }

/// Bounded de-duplicator for realtime events keyed by `eventId`. After a
/// reconnect the server may replay events; this drops ones already delivered.
class EventDeduper {
  EventDeduper({this.capacity = 500});

  final int capacity;
  final Set<String> _seen = <String>{};
  final Queue<String> _order = Queue<String>();

  bool isDuplicate(String? eventId) {
    if (eventId == null || eventId.isEmpty) return false;
    if (_seen.contains(eventId)) return true;
    _seen.add(eventId);
    _order.add(eventId);
    if (_order.length > capacity) {
      _seen.remove(_order.removeFirst());
    }
    return false;
  }
}

class RealtimeClient {
  RealtimeClient({
    required this.serverUrl,
    required this.tokenProvider,
    bool enabled = true,
    this.maxBackoff = const Duration(seconds: 30),
  }) : _enabled = enabled;

  RealtimeClient.disabled()
    : serverUrl = '',
      tokenProvider = (() async => null),
      _enabled = false,
      maxBackoff = const Duration(seconds: 30);

  final String serverUrl;
  final Future<String?> Function() tokenProvider;
  final bool _enabled;
  final Duration maxBackoff;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionState =
      StreamController<RealtimeConnectionState>.broadcast();
  final _deduper = EventDeduper();
  final _random = Random();

  io.Socket? _socket;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  bool _manualDisconnect = false;
  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;

  Stream<Map<String, dynamic>> get events => _events.stream;
  Stream<RealtimeConnectionState> get connectionState =>
      _connectionState.stream;
  RealtimeConnectionState get currentState => _state;

  Future<void> connect() async {
    if (!_enabled || _disposed) return;
    _manualDisconnect = false;
    if (_socket?.connected == true) return;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    if (!_enabled || _disposed || _manualDisconnect) return;
    _reconnectTimer?.cancel();

    // Always fetch a fresh access token so a reconnect after token rotation
    // still authenticates.
    final token = await tokenProvider();
    if (token == null) {
      _setState(RealtimeConnectionState.disconnected);
      _scheduleReconnect();
      return;
    }

    _disposeSocket();
    _setState(RealtimeConnectionState.connecting);

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .disableReconnection() // reconnection is managed here with backoff
          .build(),
    );

    socket.onConnect((_) {
      _reconnectAttempt = 0;
      _setState(RealtimeConnectionState.connected);
    });
    socket.on('event', (payload) {
      if (payload is! Map) return;
      final map = Map<String, dynamic>.from(payload);
      if (_deduper.isDuplicate(map['eventId']?.toString())) return;
      _events.add(map);
    });
    socket.onDisconnect((_) {
      _setState(RealtimeConnectionState.disconnected);
      _scheduleReconnect();
    });
    socket.onConnectError((_) {
      _setState(RealtimeConnectionState.disconnected);
      _scheduleReconnect();
    });

    socket.connect();
    _socket = socket;
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect || !_enabled) return;
    if (_reconnectTimer?.isActive == true) return;

    // Exponential backoff with jitter: 1s, 2s, 4s, ... capped at maxBackoff.
    final base = min(
      maxBackoff.inMilliseconds,
      1000 * pow(2, _reconnectAttempt).toInt(),
    );
    final jitter = _random.nextInt(500);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(milliseconds: base + jitter), () {
      unawaited(_openSocket());
    });
  }

  void typingStarted(String partnershipId) {
    _socket?.emit('typing.started', {'partnershipId': partnershipId});
  }

  void typingStopped(String partnershipId) {
    _socket?.emit('typing.stopped', {'partnershipId': partnershipId});
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _disposeSocket();
    _setState(RealtimeConnectionState.disconnected);
  }

  Future<void> dispose() async {
    _disposed = true;
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _disposeSocket();
    await _events.close();
    await _connectionState.close();
  }

  void _disposeSocket() {
    final socket = _socket;
    if (socket == null) return;
    socket.dispose();
    _socket = null;
  }

  void _setState(RealtimeConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_connectionState.isClosed) _connectionState.add(next);
  }
}
