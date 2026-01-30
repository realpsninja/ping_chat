import 'package:flutter/material.dart';
import 'custom_navigation_bar.dart';
import '../services/chat_actions_service.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/socket_service.dart';
import '../screens/auth_screen.dart'; // Добавляем импорт

class ProfileBottomSheet {
  static void show({
    required BuildContext context,
    required String nickname,
    required int userId,
    required List<dynamic> chats,
    required VoidCallback onReloadChats,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2a2a2a),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _ProfileBottomSheetContent(
          nickname: nickname,
          userId: userId,
          chats: chats,
          onReloadChats: onReloadChats,
        );
      },
    );
  }
}

class _ProfileBottomSheetContent extends StatefulWidget {
  final String nickname;
  final int userId;
  final List<dynamic> chats;
  final VoidCallback onReloadChats;

  const _ProfileBottomSheetContent({
    required this.nickname,
    required this.userId,
    required this.chats,
    required this.onReloadChats,
  });

  @override
  State<_ProfileBottomSheetContent> createState() => _ProfileBottomSheetContentState();
}

class _ProfileBottomSheetContentState extends State<_ProfileBottomSheetContent> {
  bool _deletingAccount = false;
  bool _loggingOut = false;

  Future<void> _deleteAccount() async {
    final confirmed = await CustomNavigationBar.showConfirmationDialog(
      context,
      'Удалить аккаунт?',
      'Ваш аккаунт и все связанные данные будут удалены безвозвратно.\nЭто действие нельзя отменить.',
      'Удалить',
      Colors.red,
    );
    
    if (!confirmed) return;
    
    setState(() => _deletingAccount = true);
    
    try {
      // Используем существующий эндпоинт
      await ApiService().deleteAccount();
      
      // Очищаем локальные данные
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      SocketService().disconnect();
      
      if (context.mounted) {
        // Показываем уведомление об успехе
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Аккаунт успешно удален'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Закрываем bottom sheet и переходим на экран авторизации
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const AuthScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingAccount = false);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await CustomNavigationBar.showConfirmationDialog(
      context,
      'Выйти из аккаунта?',
      'Вы уверены, что хотите выйти из аккаунта?',
      'Выйти',
      Colors.red,
    );
    
    if (!confirmed) return;
    
    setState(() => _loggingOut = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      SocketService().disconnect();
      
      if (context.mounted) {
        // Закрываем bottom sheet и переходим на экран авторизации
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const AuthScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выхода: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle иконка (линия для красоты)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // Заголовок с аватаркой, ником и кнопкой выхода
            Row(
              children: [
                // Аватарка
                CircleAvatar(
                  backgroundColor: const Color(0xFF7474d6),
                  radius: 20, // Уменьшенный размер
                  child: Text(
                    (widget.nickname.isNotEmpty ? widget.nickname : '?')[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18, // Уменьшенный размер
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Никнейм
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.nickname.isNotEmpty ? widget.nickname : 'Пользователь',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18, // Уменьшенный размер
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'ID: ${widget.userId}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Кнопка выхода
                _loadingButton(
                  isLoading: _loggingOut,
                  icon: Icons.logout,
                  color: Colors.red[400]!,
                  onTap: _logout,
                  tooltip: 'Выйти из аккаунта',
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Разделитель
            Container(
              height: 1,
              color: Colors.grey[800],
            ),
            const SizedBox(height: 16),
            
            // Меню действий
            _buildProfileMenuItem(
              icon: Icons.delete_sweep,
              title: 'Очистить все чаты',
              subtitle: 'Удалить все сообщения во всех чатах',
              color: Colors.orange,
              onTap: () async {
                Navigator.pop(context);
                final success = await ChatActionsService.clearAllChats(context, widget.chats);
                if (success && context.mounted) {
                  widget.onReloadChats();
                }
              },
            ),
            
            _buildProfileMenuItem(
              icon: Icons.delete_forever,
              title: 'Удалить все чаты',
              subtitle: 'Удалить все чаты у всех участников',
              color: Colors.red,
              onTap: () async {
                Navigator.pop(context);
                final success = await ChatActionsService.deleteAllChats(context, widget.chats);
                if (success && context.mounted) {
                  widget.onReloadChats();
                }
              },
            ),
            
            _buildProfileMenuItem(
              icon: Icons.person_remove,
              title: 'Удалить аккаунт',
              subtitle: 'Удалить аккаунт и все данные безвозвратно',
              color: Colors.red,
              onTap: _deleteAccount,
              isLoading: _deletingAccount,
            ),
            
            const SizedBox(height: 20),
            
            // Кнопка отмены
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Закрыть',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : Icon(icon, color: color),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[400], fontSize: 12),
      ),
      trailing: isLoading
          ? null
          : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: isLoading ? null : onTap,
    );
  }

  Widget _loadingButton({
    required bool isLoading,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return isLoading
        ? Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(12),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          )
        : IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: color, size: 24),
            tooltip: tooltip,
          );
  }
}