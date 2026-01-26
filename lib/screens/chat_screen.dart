import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:pointycastle/export.dart' hide State, Padding;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/socket_service.dart';

class ChatScreen extends StatefulWidget {
  final int chatId;
  final int partnerId;
  final String partnerNickname;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.partnerId,
    required this.partnerNickname,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<dynamic> _messages = [];
  final Map<int, String> _decryptedCache = {};

  bool _loading = true;
  String? _partnerPublicKey;
  int? _myUserId;

  Timer? _autoDeleteTimer;
  DateTime? _firstMessageTime;
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('userId');
    await _loadMessages();
    _listenToMessages();
    _startAutoDeleteTimer();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await ApiService().getMessages(widget.chatId);
      setState(() {
        _messages = messages;
        _loading = false;
      });

      if (_messages.isNotEmpty) {
        _firstMessageTime = DateTime.parse(_messages.first['timestamp']);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _listenToMessages() {
    _messageSubscription = SocketService().messageStream.listen((data) {
      final dynamicChatId = data['chat_id'] ?? data['chatId'];
      final chatId = dynamicChatId is String
          ? int.tryParse(dynamicChatId)
          : dynamicChatId;

      if (chatId != widget.chatId) return;

      if (data['type'] == 'deleted') {
        setState(() {
          _messages.removeWhere((m) => m['id'] == data['messageId']);
          _decryptedCache.remove(data['messageId']);
        });
        return;
      }

      setState(() {
        _messages.removeWhere((m) => m['is_local'] == true);
        _messages.add(data);
        _firstMessageTime ??= DateTime.now();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    });
  }

  void _startAutoDeleteTimer() {
    _autoDeleteTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_firstMessageTime == null) return;

      if (DateTime.now().difference(_firstMessageTime!).inMinutes >= 10) {
        await ApiService().deleteChat(widget.chatId);
        if (!mounted) return;
        Navigator.pop(context);
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      _partnerPublicKey ??=
          await ApiService().getPublicKey(widget.partnerId);

      final aesKey = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final iv = List<int>.generate(16, (_) => Random.secure().nextInt(256));

      final encryptedMessage = _encryptWithAES(
        text,
        Uint8List.fromList(aesKey),
        Uint8List.fromList(iv),
      );

      final myPublicKey = CryptoService().getPublicKeyPem();

      final encryptedKeys = <int, String>{
        widget.partnerId:
            _encryptAESKeyWithRSA(aesKey, _partnerPublicKey!),
        _myUserId!: _encryptAESKeyWithRSA(aesKey, myPublicKey),
      };

      final content = jsonEncode({
        'data': encryptedMessage,
        'iv': base64Encode(iv),
      });

      // ✅ OPTIMISTIC UI
      setState(() {
        _messages.add({
          'id': -DateTime.now().millisecondsSinceEpoch,
          'chat_id': widget.chatId,
          'sender_id': _myUserId,
          'content': content,
          'encrypted_keys': encryptedKeys.map(
            (k, v) => MapEntry(k.toString(), v),
          ),
          'is_local': true,
        });
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      SocketService().sendMessage(
        widget.chatId,
        content,
        encryptedKeys,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send error: $e')),
      );
    }
  }

  String _encryptWithAES(String message, Uint8List key, Uint8List iv) {
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    return encrypter.encrypt(message, iv: enc.IV(iv)).base64;
  }

  String _encryptAESKeyWithRSA(List<int> aesKey, String publicKeyPem) {
    final rsaPublicKey =
        CryptoService().deserializeRSAPublicKey(publicKeyPem);
    final engine = RSAEngine()
      ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));
    return base64Encode(engine.process(Uint8List.fromList(aesKey)));
  }

  String _decryptMessage(dynamic message) {
    final id = message['id'];

    if (_decryptedCache.containsKey(id)) {
      return _decryptedCache[id]!;
    }

    try {
      final content = jsonDecode(message['content']);
      final keys = Map<String, dynamic>.from(message['encrypted_keys']);
      final myKey = keys[_myUserId.toString()];
      final aesKey = CryptoService().decryptAESKey(myKey);

      final decrypted = _decryptWithAES(
        content['data'],
        aesKey,
        content['iv'],
      );

      _decryptedCache[id] = decrypted;
      return decrypted;
    } catch (e) {
      return '[Decryption failed]';
    }
  }

  String _decryptWithAES(String data, Uint8List key, String iv) {
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    return encrypter.decrypt64(data, iv: enc.IV.fromBase64(iv));
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    }
  }

  @override
  void dispose() {
    _autoDeleteTimer?.cancel();
    _messageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1c1c1e),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202020),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.partnerNickname, style: const TextStyle(color: Colors.white)),
            if (_firstMessageTime != null)
              Text(
                'Авто удаление каждые ${10 - DateTime.now().difference(_firstMessageTime!).inMinutes}мин.',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages', style: TextStyle(color: Colors.white)))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        // Оптимизация: не пересоздавать виджеты
                        addAutomaticKeepAlives: true,
                        cacheExtent: 1000,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMine = msg['sender_id'] == _myUserId;
                          final decrypted = _decryptMessage(msg);

                          return Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                              ),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMine 
                                    ? const Color(0xFF7474d6) // Ваше сообщение
                                    : const Color(0xFF474747), // Сообщение партнера
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                decrypted,
                                style: TextStyle(
                                  color: isMine ? Colors.white : Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), // 10px с боков, 10px снизу
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2f2f2f), // Фон поля ввода
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: 6, // Растягивается до 6 строк
                      minLines: 1, // Минимум 1 строка
                      decoration: const InputDecoration(
                        hintText: 'Введите сообщение...',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
