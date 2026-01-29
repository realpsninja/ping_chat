class StatusUtils {
  static String formatLastSeen(DateTime? lastSeen, bool isOnline) {
    if (isOnline) {
      return 'Онлайн';
    }
    
    if (lastSeen == null) {
      return 'Был недавно';
    }
    
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
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
        final formattedDate = '${lastSeen.day.toString().padLeft(2, '0')}.'
            '${lastSeen.month.toString().padLeft(2, '0')}.'
            '${lastSeen.year}';
        return 'Был $formattedDate';
      }
    }
  }
  
  static String _getMinutesText(int minutes) {
    if (minutes % 10 == 1 && minutes % 100 != 11) return 'минуту';
    if (minutes % 10 >= 2 && minutes % 10 <= 4 && 
        (minutes % 100 < 10 || minutes % 100 >= 20)) return 'минуты';
    return 'минут';
  }
  
  static String _getHoursText(int hours) {
    if (hours % 10 == 1 && hours % 100 != 11) return 'час';
    if (hours % 10 >= 2 && hours % 10 <= 4 && 
        (hours % 100 < 10 || hours % 100 >= 20)) return 'часа';
    return 'часов';
  }
  
  static String _getDaysText(int days) {
    if (days % 10 == 1 && days % 100 != 11) return 'день';
    if (days % 10 >= 2 && days % 10 <= 4 && 
        (days % 100 < 10 || days % 100 >= 20)) return 'дня';
    return 'дней';
  }
}