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
  
  // Добавляем новые поля для статуса онлайн
  bool _isPartnerOnline = false;
  DateTime? _partnerLastSeen;
  StreamSubscription? _presenceSubscription;
  Timer? _presenceTimer;

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
    _initPresenceTracking(); // Добавляем инициализацию отслеживания присутствия
  }
  
  // Добавляем метод для инициализации отслеживания присутствия
  void _initPresenceTracking() {
    // Получаем текущий статус партнера
    _updatePartnerPresence();
    
    // Слушаем обновления статуса из сокета
    _presenceSubscription = SocketService().presenceStream.listen((data) {
      if (data['user_id'] == widget.partnerId) {
        setState(() {
          _isPartnerOnline = data['is_online'] ?? false;
          if (data['last_seen'] != null) {
            _partnerLastSeen = DateTime.parse(data['last_seen']);
          }
        });
      }
    });
    
    // Периодически обновляем статус (каждые 30 секунд)
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updatePartnerPresence();
    });
    
    // Также обновляем статус при возвращении на экран
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final routeObserver = ModalRoute.of(context);
      routeObserver?.addScopedWillPopCallback(() async {
        _updatePartnerPresence();
        return true;
      });
    });
  }
  
  // Метод для обновления статуса присутствия партнера
  Future<void> _updatePartnerPresence() async {
    try {
      final presenceData = await ApiService().getUserPresence(widget.partnerId);
      if (presenceData != null && mounted) {
        setState(() {
          _isPartnerOnline = presenceData['is_online'] ?? false;
          if (presenceData['last_seen'] != null) {
            _partnerLastSeen = DateTime.parse(presenceData['last_seen']);
          }
        });
      }
    } catch (e) {
      print('Failed to update presence: $e');
    }
  }
  
  // Метод для форматирования времени последнего посещения
  String _formatLastSeen() {
    if (_isPartnerOnline) {
      return 'Онлайн';
    }
    
    if (_partnerLastSeen == null) {
      return 'Был недавно';
    }
    
    final now = DateTime.now();
    final difference = now.difference(_partnerLastSeen!);
    
    if (difference.inSeconds < 60) {
      return 'Был только что';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return 'Был $minutes ${_getMinutesText(minutes)} назад';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return 'Был $hours ${_getHoursText(hours)} назад';
    } else {
      final days = difference.inDays;
      if (days == 1) {
        return 'Был вчера';
      } else if (days < 7) {
        return 'Был $days ${_getDaysText(days)} назад';
      } else {
        final formattedDate = '${_partnerLastSeen!.day.toString().padLeft(2, '0')}.'
            '${_partnerLastSeen!.month.toString().padLeft(2, '0')}.'
            '${_partnerLastSeen!.year}';
        return 'Был $formattedDate';
      }
    }
  }
  
  // Вспомогательные методы для правильного склонения
  String _getMinutesText(int minutes) {
    if (minutes % 10 == 1 && minutes % 100 != 11) return 'минуту';
    if (minutes % 10 >= 2 && minutes % 10 <= 4 && 
        (minutes % 100 < 10 || minutes % 100 >= 20)) return 'минуты';
    return 'минут';
  }
  
  String _getHoursText(int hours) {
    if (hours % 10 == 1 && hours % 100 != 11) return 'час';
    if (hours % 10 >= 2 && hours % 10 <= 4 && 
        (hours % 100 < 10 || hours % 100 >= 20)) return 'часа';
    return 'часов';
  }
  
  String _getDaysText(int days) {
    if (days % 10 == 1 && days % 100 != 11) return 'день';
    if (days % 10 >= 2 && days % 10 <= 4 && 
        (days % 100 < 10 || days % 100 >= 20)) return 'дня';
    return 'дней';
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await ApiService().getMessages(widget.chatId);
      setState(() {
        _messages = messages;
        _loading = false;
      });

      if (_messages.isNotEmpty) {
        _firstMessageTime = DateTime.parse(_messages.last['timestamp']);
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

      if (data['type'] == 'cleared') {
        setState(() {
          _messages.clear();
          _decryptedCache.clear();
          _firstMessageTime = null;
        });
        return;
      }

      if (data['id'] != null) {
        // Удаляем локальное сообщение если оно есть
        final localMessageIndex = _messages.indexWhere((m) => m['is_local'] == true);
        if (localMessageIndex != -1) {
          setState(() {
            _messages.removeAt(localMessageIndex);
          });
        }

        // Добавляем сообщение с сервера только если его еще нет
        if (!_messages.any((m) => m['id'] == data['id'])) {
          setState(() {
            _messages.add(data);
            _firstMessageTime ??= DateTime.now();
          });
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    });
  }

  void _startAutoDeleteTimer() {
    _autoDeleteTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_firstMessageTime == null || _messages.isEmpty) return;

      final now = DateTime.now();
      final minutesSinceFirstMessage = now.difference(_firstMessageTime!).inMinutes;
      
      if (minutesSinceFirstMessage >= 10) {
        try {
          for (final message in _messages) {
            if (message['id'] is int && message['id'] > 0) {
              try {
                await ApiService().deleteMessage(message['id']);
              } catch (e) {
                print('Failed to delete message ${message['id']}: $e');
              }
            }
          }
          
          setState(() {
            _messages.clear();
            _decryptedCache.clear();
            _firstMessageTime = null;
          });
        } catch (e) {
          print('Auto-delete error: $e');
        }
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final messageText = text;
    _messageController.clear();

    try {
      _partnerPublicKey ??=
          await ApiService().getPublicKey(widget.partnerId);

      final aesKey = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final iv = List<int>.generate(16, (_) => Random.secure().nextInt(256));

      final encryptedMessage = _encryptWithAES(
        messageText,
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

      // Создаем уникальный локальный ID
      final localMessageId = -(DateTime.now().millisecondsSinceEpoch + _messages.length);
      
      // Сохраняем оригинальный текст для быстрого отображения
      final originalTextCache = messageText;
      
      final newMessage = {
        'id': localMessageId,
        'chat_id': widget.chatId,
        'sender_id': _myUserId,
        'content': content,
        'encrypted_keys': encryptedKeys.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
        'is_local': true,
        'original_text': originalTextCache,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Добавляем в кэш декриптированное сообщение сразу
      _decryptedCache[localMessageId] = originalTextCache;
      
      setState(() {
        _messages.add(newMessage);
        
        if (_firstMessageTime == null) {
          _firstMessageTime = DateTime.now();
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Отправляем через сокет
      final keysAsString = encryptedKeys.map((k, v) => MapEntry(k.toString(), v));
      SocketService().sendMessage(
        widget.chatId,
        content,
        Map<int, String>.from(encryptedKeys),
      );

      // Периодически проверяем, не пришло ли сообщение с сервера
      Future.delayed(const Duration(seconds: 3)).then((_) {
        if (mounted) {
          // Удаляем локальное сообщение если его нет в основном списке с сервера
          _removeLocalMessageIfDuplicate(localMessageId);
        }
      });
      
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e')),
      );
    }
  }

  void _removeLocalMessageIfDuplicate(int localMessageId) {
    final localMessageIndex = _messages.indexWhere((m) => m['id'] == localMessageId);
    if (localMessageIndex != -1) {
      setState(() {
        _messages.removeAt(localMessageIndex);
        _decryptedCache.remove(localMessageId);
      });
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

    // Проверяем, есть ли оригинальный текст (для локальных сообщений)
    if (message['original_text'] != null) {
      return message['original_text'];
    }

    // Проверяем кэш
    if (_decryptedCache.containsKey(id)) {
      return _decryptedCache[id]!;
    }

    try {
      final content = jsonDecode(message['content']);
      final keys = Map<String, dynamic>.from(message['encrypted_keys']);
      final myKey = keys[_myUserId.toString()];
      
      if (myKey == null) {
        return '[Зашифровано для другого пользователя]';
      }
      
      final aesKey = CryptoService().decryptAESKey(myKey);

      final decrypted = _decryptWithAES(
        content['data'],
        aesKey,
        content['iv'],
      );

      _decryptedCache[id] = decrypted;
      return decrypted;
    } catch (e) {
      print('Decryption error: $e');
      return '[Ошибка дешифровки]';
    }
  }

  String _decryptWithAES(String data, Uint8List key, String iv) {
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    return encrypter.decrypt64(data, iv: enc.IV.fromBase64(iv));
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _clearChatNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text(
          'Очистить чат сейчас?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Все сообщения в чате с ${widget.partnerNickname} будут удалены немедленно у всех участников.\nЭто действие нельзя отменить.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await ApiService().clearChatMessages(widget.chatId);
        
        setState(() {
          _messages.clear();
          _decryptedCache.clear();
          _firstMessageTime = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Чат очищен'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка очистки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteChatNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text(
          'Удалить чат полностью?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Чат с ${widget.partnerNickname} и все сообщения будут удалены у всех участников.\nЭто действие нельзя отменить.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await ApiService().deleteChat(widget.chatId);
        
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Чат удален'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _autoDeleteTimer?.cancel();
    _messageSubscription?.cancel();
    _presenceSubscription?.cancel(); // Отписываемся от потока присутствия
    _presenceTimer?.cancel(); // Отменяем таймер обновления статуса
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
            Text(
              _formatLastSeen(), // Используем наш метод для отображения статуса
              style: TextStyle(
                fontSize: 12, 
                color: _isPartnerOnline ? Colors.green : Colors.white70, // Зеленый если онлайн
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Добавляем индикатор онлайн-статуса рядом с меню
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: _isPartnerOnline 
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF33333e),
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            onSelected: (value) async {
              if (value == 'clear_chat') {
                await _clearChatNow();
              } else if (value == 'delete_chat') {
                await _deleteChatNow();
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'clear_chat',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Очистить чат сейчас', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete_chat',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Удалить чат полностью', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Добавляем отступ сверху
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('Нет сообщений', style: TextStyle(color: Colors.white)))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
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
                                  vertical: 3,
                              ),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMine 
                                  ? const Color(0xFF7474d6)
                                  : const Color(0xFF474747),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: const Radius.circular(14),
                                  bottomRight: const Radius.circular(0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: Text(
                                      decrypted,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 0),
                                    child: Text(
                                      _formatTime(msg['timestamp']),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white70,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2f2f2f),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: 6,
                      minLines: 1,
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
  
  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp);
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (e) {
      return '';
    }
  }
}