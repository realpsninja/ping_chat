import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _chatUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get chatUpdateStream => _chatUpdateController.stream;

  void connect(String token) {
    _socket = IO.io(
      'https://plugins.timeto.watch',
      IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setAuth({'token': token})
        .setPath('/socket.io')
        .enableForceNew()
        .build(),
    );

    _socket!.onConnect((_) => print('Socket connected'));
    _socket!.onDisconnect((_) => print('Socket disconnected'));
    _socket!.onError((err) => print('Socket error: $err'));

    _socket!.on('new_message', (data) {
      print('Received new_message: $data');
      final message = Map<String, dynamic>.from(data);
      _messageController.add(message);
      _chatUpdateController.add({'type': 'new_message', 'data': message});
    });

    _socket!.on('message_deleted', (data) {
      print('Received message_deleted: $data');
      _messageController.add({
        'type': 'deleted',
        'messageId': data['messageId'],
        'chatId': data['chatId'],
      });
      _chatUpdateController.add({'type': 'message_deleted', 'data': data});
    });

    _socket!.on('user_status_changed', (data) {
      print('Received user_status_changed: $data');
      _statusController.add(Map<String, dynamic>.from(data));
    });

    // Добавляем обработку для очистки сообщений
    _socket!.on('messages_cleared', (data) {
      print('Received messages_cleared: $data');
      _messageController.add({
        'type': 'cleared',
        'chatId': data['chatId'],
      });
    });
  }

  void sendMessage(int chatId, String encryptedContent, Map<int, String> encryptedKeys) {
    final Map<String, String> keysAsString = {};
    encryptedKeys.forEach((key, value) {
      keysAsString[key.toString()] = value;
    });

    final messageData = {
      'chatId': chatId,
      'content': encryptedContent,
      'encryptedKeys': keysAsString,
    };

    print('Sending message: $messageData');
    _socket?.emit('send_message', messageData);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
  }

  void dispose() {
    _messageController.close();
    _statusController.close();
    _chatUpdateController.close();
  }
}