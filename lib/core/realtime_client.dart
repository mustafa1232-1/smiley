import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

class RealtimeClient {
  RealtimeClient({
    required this.serverUrl,
    required this.tokenProvider,
    bool enabled = true,
  }) : _enabled = enabled;

  RealtimeClient.disabled()
      : serverUrl = '',
        tokenProvider = (() async => null),
        _enabled = false;

  final String serverUrl;
  final Future<String?> Function() tokenProvider;
  final bool _enabled;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  io.Socket? _socket;

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> connect() async {
    if (!_enabled || _socket?.connected == true) return;

    final token = await tokenProvider();
    if (token == null) return;

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );

    socket.on('event', (payload) {
      if (payload is Map) {
        _events.add(Map<String, dynamic>.from(payload));
      }
    });
    socket.connect();
    _socket = socket;
  }

  void typingStarted(String partnershipId) {
    _socket?.emit('typing.started', {'partnershipId': partnershipId});
  }

  void typingStopped(String partnershipId) {
    _socket?.emit('typing.stopped', {'partnershipId': partnershipId});
  }

  Future<void> disconnect() async {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
