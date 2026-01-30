import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/crypto_service.dart';
import '../services/chat_actions_service.dart';
import '../widgets/custom_navigation_bar.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:typed_data';
import 'chat_screen.dart';
import 'search_screen.dart';
import 'auth_screen.dart';
import '../utils/status_utils.dart';

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
  final Map<int, int> _unreadCounts = {};
  
  final Map<int, bool> _partnerOnlineStatus = {};
  final Map<int, DateTime?> _partnerLastSeen = {};
  Timer? _statusTimer;
  StreamSubscription? _presenceSubscription;
  
  int _currentIndex = 0;

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
    _initPresenceTracking();
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
          
          if (lastMessageData != null && lastMessageData != 'Нет сообщений') {
            if (lastMessageData is String && lastMessageData.isNotEmpty) {
              if (lastMessageData.startsWith('{') && lastMessageData.contains('"data"')) {
                try {
                  final parsedMessage = jsonDecode(lastMessageData);
                  decryptedMessage = _decryptMessageContent(parsedMessage);
                } catch (e) {
                  decryptedMessage = lastMessageData.length > 50 
                      ? '${lastMessageData.substring(0, 50)}...' 
                      : lastMessageData;
                }
              } else {
                decryptedMessage = lastMessageData.length > 50 
                    ? '${lastMessageData.substring(0, 50)}...' 
                    : lastMessageData;
              }
            } else if (lastMessageData is Map) {
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
      
      for (final chat in processedChats) {
        final chatId = chat['id'];
        final unreadCount = chat['unread_count'] ?? 0;
        _unreadCounts[chatId] = unreadCount;
      }
      
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

  void _initPresenceTracking() {
    _updateAllPartnerStatuses();
    
    _presenceSubscription = SocketService().presenceStream.listen((data) {
      final partnerId = data['user_id'];
      final isOnline = data['is_online'] ?? false;
      final lastSeen = data['last_seen'] != null 
          ? DateTime.parse(data['last_seen'])
          : null;
      
      setState(() {
        _partnerOnlineStatus[partnerId] = isOnline;
        _partnerLastSeen[partnerId] = lastSeen;
      });
    });
    
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateAllPartnerStatuses();
    });
  }
  
  Future<void> _updateAllPartnerStatuses() async {
    for (final chat in _chats) {
      final partnerId = chat['partner_id'];
      try {
        final presenceData = await ApiService().getUserPresence(partnerId);
        if (presenceData != null && mounted) {
          setState(() {
            _partnerOnlineStatus[partnerId] = presenceData['is_online'] ?? false;
            if (presenceData['last_seen'] != null) {
              _partnerLastSeen[partnerId] = DateTime.parse(presenceData['last_seen']);
            }
          });
        }
      } catch (e) {
        print('Failed to update presence for user $partnerId: $e');
      }
    }
  }

  void _listenToSocketEvents() {
    _chatSubscription = SocketService().chatUpdateStream.listen((event) {
      if (event['type'] == 'deleted') {
        setState(() {
          _chats.removeWhere((chat) => chat['id'] == event['chatId']);
          _unreadCounts.remove(event['chatId']);
        });
      } else {
        _loadChats();
      }
    });

    _messageSubscription = SocketService().messageStream.listen((data) {
      final dynamicChatId = data['chat_id'] ?? data['chatId'];
      final chatId = dynamicChatId is String
          ? int.tryParse(dynamicChatId)
          : dynamicChatId;
      
      if (chatId != null) {
        if (data['type'] != 'deleted' && data['id'] != null && data['sender_id'] != _myUserId) {
          final currentCount = _unreadCounts[chatId] ?? 0;
          _unreadCounts[chatId] = currentCount + 1;
          
          setState(() {
            final index = _chats.indexWhere((chat) => chat['id'] == chatId);
            if (index != -1) {
              _chats[index]['unread_count'] = _unreadCounts[chatId];
              _chats[index]['last_message'] = _getMessagePreview(data);
              _chats[index]['last_message_time'] = data['timestamp'] ?? DateTime.now().toIso8601String();
              _chats[index]['last_message_sender_id'] = data['sender_id'];
              
              final updatedChat = _chats.removeAt(index);
              _chats.insert(0, updatedChat);
            }
          });
        }
      }
    });
  }

  String _getMessagePreview(dynamic messageData) {
    try {
      final content = messageData['content'] ?? '';
      
      String decryptedPreview = 'Сообщение';
      
      if (content is String && content.isNotEmpty) {
        if (content.startsWith('{') && content.contains('"data"')) {
          try {
            final parsedMessage = jsonDecode(content);
            decryptedPreview = _decryptMessageContent(parsedMessage);
          } catch (e) {
            decryptedPreview = 'Зашифрованное сообщение';
          }
        } else {
          decryptedPreview = content.length > 50 
              ? '${content.substring(0, 50)}...' 
              : content;
        }
      }
      
      return decryptedPreview;
    } catch (e) {
      return 'Сообщение';
    }
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
    _presenceSubscription?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _markChatAsRead(int chatId) async {
    setState(() {
      _unreadCounts.remove(chatId);
      
      final index = _chats.indexWhere((chat) => chat['id'] == chatId);
      if (index != -1) {
        _chats[index]['unread_count'] = 0;
      }
    });
  }

  void _openChat(BuildContext context, dynamic chat) async {
    await _markChatAsRead(chat['id']);
    
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
      if (messageData is String) {
        return messageData.isEmpty || messageData == 'Нет сообщений' 
            ? 'Нет сообщений' 
            : messageData;
      }
      
      if (messageData == null) {
        return 'Нет сообщений';
      }
      
      if (messageData is Map<String, dynamic>) {
        final content = messageData['content'] ?? '';
        final keys = messageData['encrypted_keys'];
        
        if (content.isEmpty || keys == null) {
          return 'Нет сообщений';
        }
        
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
        
        if (_myUserId == null) {
          return 'Зашифрованное сообщение';
        }
        
        final myKey = keysMap[_myUserId.toString()];
        if (myKey == null) {
          return 'Зашифрованное сообщение';
        }
        
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

  // Обработка навигации
  void _onNavigationItemSelected(int index) {
    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0: // Чаты (уже на этой странице)
        break;
      case 1: // Поиск
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SearchScreen()),
        ).then((_) => _loadChats());
        setState(() => _currentIndex = 0);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1c1c1c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1c1c1c),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ваши чаты',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19, // Уменьшенный размер
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_nickname != null && _nickname!.isNotEmpty)
              Text(
                'Ваш никнейм: ${_nickname!}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14, // Меньший размер для ника
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF2a2a2a),
              radius: 20,
              child: IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 22),
                padding: EdgeInsets.zero,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  ).then((_) => _loadChats());
                },
              ),
            ),
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
                      final partnerId = chat['partner_id'];
                      final isOnline = _partnerOnlineStatus[partnerId] ?? false;
                      final lastSeen = _partnerLastSeen[partnerId];
                      final statusText = StatusUtils.formatLastSeen(lastSeen, isOnline);
                      final unreadCount = chat['unread_count'] ?? 0;
                      
                      return Container(
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
                            vertical: 12,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF7474d6),
                            radius: 24,
                            child: Text(
                              (chat['partner_nickname'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  chat['partner_nickname'] ?? 'Unknown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (chat['last_message_time'] != null)
                                Text(
                                  _formatTime(chat['last_message_time']),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: isOnline ? Colors.green : Colors.grey[300],
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          trailing: unreadCount > 0
                            ? Container(
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
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : null,
                          onTap: () => _openChat(context, chat),
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
                                        onTap: () async {
                                          Navigator.pop(context);
                                          final success = await ChatActionsService.clearChat(
                                            context,
                                            chat['id'],
                                            chat['partner_nickname'],
                                          );
                                          if (success && mounted) {
                                            final index = _chats.indexWhere((c) => c['id'] == chat['id']);
                                            if (index != -1) {
                                              setState(() {
                                                _chats[index]['last_message'] = 'Нет сообщений';
                                                _chats[index]['last_message_time'] = null;
                                                _chats[index]['unread_count'] = 0;
                                                _unreadCounts.remove(chat['id']);
                                              });
                                            }
                                          }
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
                                        onTap: () async {
                                          Navigator.pop(context);
                                          final success = await ChatActionsService.deleteChat(
                                            context,
                                            chat['id'],
                                            chat['partner_nickname'],
                                          );
                                          if (success && mounted) {
                                            setState(() {
                                              _chats.removeWhere((c) => c['id'] == chat['id']);
                                              _unreadCounts.remove(chat['id']);
                                            });
                                          }
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
                      );
                    },
                  ),
            ),
      bottomNavigationBar: CustomNavigationBar(
        currentIndex: _currentIndex,
        onItemSelected: _onNavigationItemSelected,
        showNavBar: true,
        chats: _chats,
        nickname: _nickname,
        userId: _myUserId,
        onReloadChats: _loadChats,
      ),
    );
  }
}