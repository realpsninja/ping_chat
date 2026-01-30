import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChatActionsService {
  // Удалить конкретный чат
  static Future<bool> deleteChat(
    BuildContext context,
    int chatId,
    String partnerNickname,
  ) async {
    final confirmed = await showConfirmationDialog(
      context,
      'Удалить чат?',
      'Чат с $partnerNickname будет удален у всех участников.\nЭто действие нельзя отменить.',
      'Удалить',
      Colors.red,
    );
    
    if (!confirmed) return false;
    
    try {
      await ApiService().deleteChat(chatId);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Чат с $partnerNickname удален'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
  
  // Очистить конкретный чат
  static Future<bool> clearChat(
    BuildContext context,
    int chatId,
    String partnerNickname,
  ) async {
    final confirmed = await showConfirmationDialog(
      context,
      'Очистить чат?',
      'Все сообщения в чате с $partnerNickname будут удалены у всех участников.\nЭто действие нельзя отменить.',
      'Очистить',
      Colors.orange,
    );
    
    if (!confirmed) return false;
    
    try {
      await ApiService().clearChatMessages(chatId);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Чат с $partnerNickname очищен'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка очистки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
  
  // Удалить все чаты
  static Future<bool> deleteAllChats(
    BuildContext context,
    List<dynamic> chats,
  ) async {
    final confirmed = await showConfirmationDialog(
      context,
      'Удалить все чаты?',
      'Все ваши чаты будут удалены у всех участников.\nЭто действие нельзя отменить.',
      'Удалить все',
      Colors.red,
    );
    
    if (!confirmed) return false;
    
    try {
      for (final chat in chats) {
        await ApiService().deleteChat(chat['id']);
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Все чаты удалены'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
  
  // Очистить все чаты
  static Future<bool> clearAllChats(
    BuildContext context,
    List<dynamic> chats,
  ) async {
    final confirmed = await showConfirmationDialog(
      context,
      'Очистить все чаты?',
      'Все сообщения во всех ваших чатах будут удалены у всех участников.\nЭто действие нельзя отменить.',
      'Очистить все',
      Colors.orange,
    );
    
    if (!confirmed) return false;
    
    try {
      for (final chat in chats) {
        await ApiService().clearChatMessages(chat['id']);
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Все чаты очищены'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка очистки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
  
  // Публичный метод для показа диалога подтверждения
  static Future<bool> showConfirmationDialog(
    BuildContext context,
    String title,
    String content,
    String confirmText,
    Color confirmColor,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: TextStyle(color: Colors.grey[300])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
    
    return confirmed ?? false;
  }
}