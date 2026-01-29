import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/crypto_service.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:typed_data';
import 'chat_screen.dart';
import 'search_screen.dart';
import 'auth_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<dynamic> _chats = [];
  bool _loading = true;
  String? _nickname;
  int? _myUserId;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _messageSubscription;
  Timer? _refreshTimer;
  final Map<int, bool> _isSwiped = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('userId');
    await _loadNickname();
    await _loadChats();
    _listenToSocketEvents();
    _startAutoRefresh();
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _nickname = prefs.getString('nickname'));
  }

  Future<void> _loadChats() async {
    try {
      final chats = await ApiService().getChats();
      
      final processedChats = await Future.wait(chats.map((chat) async {
        try {
          final lastMessageData = chat['last_message'];
          String decryptedMessage = 'Нет сообщений';
          
          // Проверяем наличие данных о последнем сообщении
          if (lastMessageData != null && lastMessageData != 'Нет сообщений') {
            // Если это строка с JSON, пытаемся распарсить
            if (lastMessageData is String && lastMessageData.isNotEmpty) {
              // Проверяем, не является ли это уже расшифрованным текстом
              if (lastMessageData.startsWith('{') && lastMessageData.contains('"data"')) {
                // Это JSON - пытаемся расшифровать
                try {
                  final parsedMessage = jsonDecode(lastMessageData);
                  decryptedMessage = _decryptMessageContent(parsedMessage);
                } catch (e) {
                  // Если не удалось распарсить как JSON, возможно это уже текст
                  decryptedMessage = lastMessageData.length > 50 
                      ? '${lastMessageData.substring(0, 50)}...' 
                      : lastMessageData;
                }
              } else {
                // Это уже текст
                decryptedMessage = lastMessageData.length > 50 
                    ? '${lastMessageData.substring(0, 50)}...' 
                    : lastMessageData;
              }
            } else if (lastMessageData is Map) {
              // Если это уже Map, пытаемся расшифровать
              decryptedMessage = _decryptMessageContent(lastMessageData);
            }
          }
          
          return {
            ...chat,
            'last_message': decryptedMessage,
          };
        } catch (e) {
          print('Error processing chat ${chat['id']}: $e');
          return {
            ...chat,
            'last_message': 'Нет сообщений',
          };
        }
      }));
      
      // Сортируем по времени последнего сообщения
      processedChats.sort((a, b) {
        final timeA = DateTime.tryParse(a['last_message_time'] ?? '') ?? DateTime(1970);
        final timeB = DateTime.tryParse(b['last_message_time'] ?? '') ?? DateTime(1970);
        return timeB.compareTo(timeA);
      });
      
      setState(() {
        _chats = processedChats;
        _loading = false;
      });
    } catch (e) {
      print('Error loading chats: $e');
      setState(() => _loading = false);
    }
  }

  void _listenToSocketEvents() {
    _chatSubscription = SocketService().chatUpdateStream.listen((event) {
      _loadChats();
    });

    _messageSubscription = SocketService().messageStream.listen((data) {
      final dynamicChatId = data['chat_id'] ?? data['chatId'];
      final chatId = dynamicChatId is String
          ? int.tryParse(dynamicChatId)
          : dynamicChatId;
      
      if (chatId != null) {
        if (data['type'] != 'deleted' && data['id'] != null) {
          _loadChats();
        }
      }
    });
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _loadChats();
      }
    });
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _messageSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text(
          'Выйти из аккаунта?',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      SocketService().disconnect();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen(savedNickname: null)),
      );
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inHours < 1) return '${diff.inMinutes}м';
      if (diff.inDays < 1) return '${diff.inHours}ч';
      return '${diff.inDays}д';
    } catch (e) {
      return '';
    }
  }

  String _decryptMessageContent(dynamic messageData) {
    try {
      // Если messageData уже является строкой (уже расшифровано или просто текст)
      if (messageData is String) {
        return messageData.isEmpty || messageData == 'Нет сообщений' 
            ? 'Нет сообщений' 
            : messageData;
      }
      
      // Если messageData не существует или пусто
      if (messageData == null) {
        return 'Нет сообщений';
      }
      
      // Если messageData - это Map (JSON структура сообщения)
      if (messageData is Map<String, dynamic>) {
        final content = messageData['content'] ?? '';
        final keys = messageData['encrypted_keys'];
        
        // Проверяем, есть ли вообще данные для расшифровки
        if (content.isEmpty || keys == null) {
          return 'Нет сообщений';
        }
        
        // Пытаемся получить зашифрованные ключи
        Map<String, dynamic> keysMap;
        if (keys is String) {
          try {
            keysMap = jsonDecode(keys);
          } catch (_) {
            return 'Нет сообщений';
          }
        } else if (keys is Map<String, dynamic>) {
          keysMap = keys;
        } else {
          return 'Нет сообщений';
        }
        
        // Проверяем, есть ли ключ для текущего пользователя
        if (_myUserId == null) {
          return 'Зашифрованное сообщение';
        }
        
        final myKey = keysMap[_myUserId.toString()];
        if (myKey == null) {
          return 'Зашифрованное сообщение';
        }
        
        // Парсим контент
        Map<String, dynamic> contentJson;
        if (content is String) {
          try {
            contentJson = jsonDecode(content);
          } catch (_) {
            return 'Нет сообщений';
          }
        } else if (content is Map<String, dynamic>) {
          contentJson = content;
        } else {
          return 'Нет сообщений';
        }
        
        final encryptedData = contentJson['data'];
        final ivBase64 = contentJson['iv'];
        
        if (encryptedData == null || ivBase64 == null) {
          return 'Нет сообщений';
        }
        
        try {
          final decryptedAESKey = CryptoService().decryptAESKey(myKey.toString());
          final result = _decryptWithAES(
            encryptedData.toString(),
            decryptedAESKey,
            ivBase64.toString(),
          );
          
          // Обрезаем слишком длинные сообщения для предпросмотра
          return result.length > 50 ? '${result.substring(0, 50)}...' : result;
        } catch (e) {
          print('Decryption error in chat list: $e');
          return 'Зашифрованное сообщение';
        }
      }
      
      return 'Нет сообщений';
    } catch (e) {
      print('Error decrypting message content: $e');
      return 'Сообщение';
    }
  }

  String _decryptWithAES(String encryptedData, Uint8List aesKey, String ivBase64) {
    try {
      final key = enc.Key(aesKey);
      final iv = enc.IV.fromBase64(ivBase64);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(encryptedData, iv: iv);
    } catch (e) {
      return 'Ошибка дешифровки';
    }
  }

  String _getMessagePrefix(dynamic chat) {
    final lastMessageSenderId = chat['last_message_sender_id'];
    if (lastMessageSenderId == _myUserId) {
      return 'Вы: ';
    }
    return '';
  }

  void _closeSwipe(int chatId) {
    setState(() {
      _isSwiped.remove(chatId);
    });
  }

  Future<void> _deleteChat(dynamic chat) async {
    _closeSwipe(chat['id']);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text(
          'Удалить чат?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Чат с ${chat['partner_nickname']} будет удален у всех участников.\nЭто действие нельзя отменить.',
          style: TextStyle(color: Colors.grey[300]),
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
        await ApiService().deleteChat(chat['id']);
        
        setState(() {
          _chats.removeWhere((c) => c['id'] == chat['id']);
        });
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Чат с ${chat['partner_nickname']} удален'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearChat(dynamic chat) async {
    _closeSwipe(chat['id']);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text(
          'Очистить чат?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Все сообщения в чате с ${chat['partner_nickname']} будут удалены у всех участников.\nЭто действие нельзя отменить.',
          style: TextStyle(color: Colors.grey[300]),
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
        await ApiService().clearChatMessages(chat['id']);
        
        setState(() {
          final index = _chats.indexWhere((c) => c['id'] == chat['id']);
          if (index != -1) {
            _chats[index]['last_message'] = 'Нет сообщений';
            _chats[index]['last_message_time'] = null;
            _chats[index]['unread_count'] = 0;
          }
        });
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Чат с ${chat['partner_nickname']} очищен'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка очистки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Закрываем все открытые свайпы при тапе на экран
        if (_isSwiped.isNotEmpty) {
          setState(() {
            _isSwiped.clear();
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1c1c1c),
        appBar: AppBar(
          backgroundColor: const Color(0xFF202020),
          title: Text(
            _nickname ?? 'Чаты',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF33333e),
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              onSelected: (value) {
                if (value == 'logout') {
                  _logout();
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Выйти', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadChats,
              backgroundColor: const Color(0xFF202020),
              color: Colors.white,
              child: _chats.isEmpty
                ? const Center(
                    child: Text(
                      'Актуальных переписок нет',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : ListView.builder(
                    itemCount: _chats.length,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      final lastMessage = chat['last_message'] ?? 'Нет сообщений';
                      final messagePrefix = _getMessagePrefix(chat);
                      final displayMessage = '$messagePrefix$lastMessage';
                      final isSwipedOpen = _isSwiped[chat['id']] == true;
                      
                      return GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          if (details.delta.dx < -5 && !isSwipedOpen) {
                            // Свайп влево - показываем кнопки
                            setState(() {
                              // Закрываем все другие свайпы
                              _isSwiped.clear();
                              _isSwiped[chat['id']] = true;
                            });
                          } else if (details.delta.dx > 5 && isSwipedOpen) {
                            // Свайп вправо - скрываем кнопки
                            _closeSwipe(chat['id']);
                          }
                        },
                        child: Stack(
                          children: [
                            // Фон с кнопками (показывается при свайпе)
                            if (isSwipedOpen)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.transparent,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            _buildActionButton(
                                              icon: Icons.delete_sweep,
                                              color: Colors.orange,
                                              label: 'Очистить',
                                              onTap: () => _clearChat(chat),
                                            ),
                                            const SizedBox(width: 6),
                                            _buildActionButton(
                                              icon: Icons.delete_forever,
                                              color: Colors.red,
                                              label: 'Удалить',
                                              onTap: () => _deleteChat(chat),
                                            ),
                                            const SizedBox(width: 16),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            
                            // Основной контент чата
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              transform: Matrix4.translationValues(
                                isSwipedOpen ? -200 : 0,
                                0,
                                0,
                              ),
                              curve: Curves.easeInOut,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1c1c1c),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey[800]!,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF7474d6),
                                    child: Text(
                                      (chat['partner_nickname'] ?? '?')[0].toUpperCase(),
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  title: Text(
                                    chat['partner_nickname'] ?? 'Unknown',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    displayMessage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[300],
                                      fontSize: 14,
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // Время показываем только когда свайп закрыт
                                      if (!isSwipedOpen && chat['last_message_time'] != null)
                                        Text(
                                          _formatTime(chat['last_message_time']),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      // Счётчик непрочитанных показываем всегда
                                      if (chat['unread_count'] != null && chat['unread_count'] > 0)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          child: Text(
                                            chat['unread_count'] > 99 ? '99+' : '${chat['unread_count']}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                    ],
                                  ),
                                  onTap: () {
                                    if (isSwipedOpen) {
                                      // Если свайп открыт, закрываем его
                                      _closeSwipe(chat['id']);
                                    } else {
                                      // Иначе открываем чат
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            chatId: chat['id'],
                                            partnerId: chat['partner_id'],
                                            partnerNickname: chat['partner_nickname'],
                                          ),
                                        ),
                                      ).then((_) => _loadChats());
                                    }
                                  },
                                  onLongPress: () {
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: const Color(0xFF2a2a2a),
                                      builder: (context) {
                                        return SafeArea(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ListTile(
                                                leading: const Icon(Icons.delete_sweep, color: Colors.orange),
                                                title: const Text(
                                                  'Очистить чат',
                                                  style: TextStyle(color: Colors.white),
                                                ),
                                                subtitle: const Text(
                                                  'Удалить все сообщения у всех участников',
                                                  style: TextStyle(color: Colors.grey),
                                                ),
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _clearChat(chat);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(Icons.delete_forever, color: Colors.red),
                                                title: const Text(
                                                  'Удалить чат',
                                                  style: TextStyle(color: Colors.white),
                                                ),
                                                subtitle: const Text(
                                                  'Удалить чат полностью у всех участников',
                                                  style: TextStyle(color: Colors.grey),
                                                ),
                                                onTap: () {
                                                  Navigator.pop(context);
                                                  _deleteChat(chat);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(Icons.cancel, color: Colors.grey),
                                                title: const Text(
                                                  'Отмена',
                                                  style: TextStyle(color: Colors.white),
                                                ),
                                                onTap: () => Navigator.pop(context),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF7474d6),
          child: const Icon(Icons.search, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ).then((_) => _loadChats());
          },
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
