import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import '../crypto/e2ee.dart';
import 'api_client.dart';
import 'local_db.dart';
import 'notification_service.dart';

class SocketClient {
  static final SocketClient instance = SocketClient._init();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;

  final List<Function(int senderId, String text)> _messageListeners = [];
  final List<Function()> _connectionListeners = [];

  final Set<String> _seenMessageIds = {};
  static const int _maxTimestampSkewMs = 5 * 60 * 1000;
  static final Random _random = Random.secure();

  SocketClient._init();

  bool get isConnected => _isConnected;

  String _generateMessageId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rnd = _random.nextInt(1 << 24);
    return "$ts-$rnd";
  }

  int? _parseOriginalLength(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _isReplayOrInvalid(Map<String, dynamic> payload) {
    final messageId = payload['message_id'] as String?;
    if (messageId == null || messageId.isEmpty) return true;

    if (_seenMessageIds.contains(messageId)) {
      print("Anti-replay: duplicate message $messageId rejected");
      return true;
    }

    final timestampStr = payload['timestamp'] as String?;
    if (timestampStr == null) return true;

    final timestamp = int.tryParse(timestampStr);
    if (timestamp == null) return true;

    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - timestamp).abs() > _maxTimestampSkewMs) {
      print("Anti-replay: stale timestamp $timestampStr for $messageId");
      return true;
    }

    _seenMessageIds.add(messageId);
    if (_seenMessageIds.length > 2000) {
      _seenMessageIds.clear();
    }
    return false;
  }

  void addMessageListener(Function(int senderId, String text) listener) {
    _messageListeners.add(listener);
  }

  void removeMessageListener(Function(int senderId, String text) listener) {
    _messageListeners.remove(listener);
  }

  void addConnectionListener(Function() listener) {
    _connectionListeners.add(listener);
  }

  void removeConnectionListener(Function() listener) {
    _connectionListeners.remove(listener);
  }

  Future<void> connect() async {
    final userId = ApiClient.instance.userId;
    if (userId == null || _isConnected || _isConnecting) return;

    _isConnecting = true;
    final serverUrl = ApiClient.instance.baseUrl.replaceAll("http://", "ws://").replaceAll("https://", "wss://");
    final wsUrl = "$serverUrl/ws/$userId";

    print("Connecting to WebSocket: $wsUrl");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _isConnecting = false;
      _notifyConnectionChanged();

      _channel!.stream.listen(
        (message) => _onMessageReceived(message),
        onError: (err) {
          print("WebSocket error: $err");
          _handleDisconnect();
        },
        onDone: () {
          print("WebSocket stream completed.");
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      await fetchOfflineMessages();
    } catch (e) {
      print("WebSocket connect exception: $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _channel = null;
    _notifyConnectionChanged();
    Timer(const Duration(seconds: 5), () {
      connect();
    });
  }

  void disconnect() {
    _channel?.sink.close(status.goingAway);
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _notifyConnectionChanged();
  }

  void _notifyConnectionChanged() {
    for (var listener in _connectionListeners) {
      try {
        listener();
      } catch (e) {
        print("Connection listener callback err: $e");
      }
    }
  }

  Future<void> _onMessageReceived(String rawMessage) async {
    try {
      final payload = jsonDecode(rawMessage);
      final type = payload['type'];

      if (type == 'message') {
        final serverMessageId = payload['id'] as int;
        final senderId = payload['sender_id'] as int;
        final ciphertext = payload['ciphertext'] as String;
        final iv = payload['iv'] as String;
        final ephemeralKey = payload['ephemeral_public_key'] as String;
        final mac = payload['mac'] as String;
        final createdAt = payload['created_at'] as String? ?? DateTime.now().toIso8601String();

        final messageId = payload['message_id'] as String?;
        if (messageId == null) return;
        if (_isReplayOrInvalid(payload)) return;

        final originalLength = _parseOriginalLength(payload['original_length']);
        if (originalLength == null || originalLength < 1) return;

        final decryptedText = await E2EEManager.decryptMessage(
          myPrivateKeyHex: ApiClient.instance.privateKeyHex!,
          senderEphemeralPublicKeyHex: ephemeralKey,
          ciphertextHex: ciphertext,
          ivHex: iv,
          macHex: mac,
          messageId: messageId,
          originalLength: originalLength,
        );

        await LocalDatabaseHelper.instance.insertMessage({
          'server_message_id': serverMessageId,
          'sender_id': senderId,
          'recipient_id': ApiClient.instance.userId!,
          'message_text': decryptedText,
          'created_at': createdAt,
          'is_read': 0,
        });

        if (senderId != ApiClient.instance.userId) {
          try {
            final profile = await ApiClient.instance.getProfile(senderId);
            final username = profile['username'] as String? ?? "Utilisateur";
            await NotificationService.instance.showMessageNotification(
              senderId: senderId,
              username: username,
              messageText: decryptedText,
            );
          } catch (_) {}
        }

        for (var listener in _messageListeners) {
          listener(senderId, decryptedText);
        }
      } else if (type == 'ack') {
        final serverMessageId = payload['id'] as int;
        final recipientId = payload['recipient_id'] as int;
        final createdAt = payload['created_at'] as String?;

        final db = await LocalDatabaseHelper.instance.database;
        await db.execute(
          'UPDATE local_messages SET server_message_id = ?, created_at = ? WHERE id = (SELECT MAX(id) FROM local_messages WHERE server_message_id IS NULL AND sender_id = ? AND recipient_id = ?)',
          [serverMessageId, createdAt ?? DateTime.now().toIso8601String(), ApiClient.instance.userId, recipientId],
        );
      }
    } catch (e) {
      print("Error handling WebSocket message: $e");
    }
  }

  Future<bool> sendEncryptedMessage({
    required int recipientId,
    required String recipientPublicKeyHex,
    required String plaintext,
  }) async {
      if (!_isConnected || _channel == null) {
      return false;
    }

    try {
      final messageId = _generateMessageId();

      final cryptoPayload = await E2EEManager.encryptMessage(
        plaintext: plaintext,
        recipientPublicKeyHex: recipientPublicKeyHex,
        messageId: messageId,
      );

      final requestPayload = {
        "recipient_id": recipientId,
        "ciphertext": cryptoPayload['ciphertext'],
        "iv": cryptoPayload['iv'],
        "ephemeral_public_key": cryptoPayload['ephemeral_public_key'],
        "mac": cryptoPayload['mac'],
        "message_id": cryptoPayload['message_id'],
        "timestamp": cryptoPayload['timestamp'],
        "original_length": cryptoPayload['original_length'],
      };

      _channel!.sink.add(jsonEncode(requestPayload));

      await LocalDatabaseHelper.instance.insertMessage({
        'server_message_id': null,
        'sender_id': ApiClient.instance.userId!,
        'recipient_id': recipientId,
        'message_text': plaintext,
        'created_at': DateTime.now().toIso8601String(),
        'is_read': 1,
      });

      return true;
    } catch (e) {
      print("Error sending encrypted message: $e");
      return false;
    }
  }

  Future<void> fetchOfflineMessages() async {
    try {
      final offlineMessages = await ApiClient.instance.getOfflineMessages();
      for (var msg in offlineMessages) {
        final serverMessageId = msg['id'] as int;
        final senderId = msg['sender_id'] as int;
        final ciphertext = msg['ciphertext'] as String;
        final iv = msg['iv'] as String;
        final ephemeralKey = msg['ephemeral_public_key'] as String;
        final mac = msg['mac'] as String;
        final createdAt = msg['created_at'] as String;

        final messageId = msg['message_id'] as String?;
        if (messageId == null) continue;
        if (_isReplayOrInvalid(msg)) continue;

        final originalLength = _parseOriginalLength(msg['original_length']);
        if (originalLength == null || originalLength < 1) continue;

        final decryptedText = await E2EEManager.decryptMessage(
          myPrivateKeyHex: ApiClient.instance.privateKeyHex!,
          senderEphemeralPublicKeyHex: ephemeralKey,
          ciphertextHex: ciphertext,
          ivHex: iv,
          macHex: mac,
          messageId: messageId,
          originalLength: originalLength,
        );

        await LocalDatabaseHelper.instance.insertMessage({
          'server_message_id': serverMessageId,
          'sender_id': senderId,
          'recipient_id': ApiClient.instance.userId!,
          'message_text': decryptedText,
          'created_at': createdAt,
          'is_read': 0,
        });

        for (var listener in _messageListeners) {
          listener(senderId, decryptedText);
        }
      }
    } catch (e) {
      print("Error fetching offline messages: $e");
    }
  }
}
