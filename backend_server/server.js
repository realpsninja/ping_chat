const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const { Pool } = require('pg');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const cors = require('cors');

const app = express();
const server = http.createServer(app);

const io = socketIo(server, {
  cors: {
    origin: "https://plugins.timeto.watch",
    methods: ["GET", "POST"],
    credentials: true
  },
  transports: ['websocket', 'polling'],
  path: '/socket.io'
});

app.use(cors());
app.use(express.json());
app.use(express.static('public'));
app.set('trust proxy', 1);

const pool = new Pool({
  user: 'dtabase_use',
  host: 'localhost',
  database: 'database_namr',
  password: 'database_password',
  port: 5432,
});

const JWT_SECRET = 'your-super-secret-jwt-key-change-this-in-production';
const SALT_ROUNDS = 10;

const NICKNAMES = [
  'wolf', 'fox', 'bear', 'void', 'raven', 'flame', 'storm', 'ice', 'rex', 'vox',
  'tiger', 'siz', 'lion', 'hawk', 'eagle', 'owl', 'falcon', 'snake',
  'shark', 'puma', 'lynx', 'boar', 'ox', 'bull', 'rhino', 'bat', 'spider', 'scorpion',
  'viper', 'cobra', 'jackal', 'hound', 'gorilla', 'panther', 'leopard', 'fire', 'wind', 'earth',
  'water', 'stone', 'rock', 'sand', 'frost', 'blaze', 'ember', 'vortex', 'tide', 'wave',
  'magma', 'thunder', 'shadow', 'abyss', 'chaos', 'order', 'light', 'dark', 'dusk', 'dawn',
  'night', 'day', 'moon', 'sun', 'star', 'sky', 'cloud', 'rain', 'leaf', 'root',
  'pine', 'oak', 'ash', 'gloom', 'doom', 'rage', 'wrath', 'fury', 'ghost', 'soul',
  'mind', 'zen', 'echo', 'pulse', 'surge', 'drift', 'flux', 'spark', 'bolt', 'flash',
  'gleam', 'glow', 'shade', 'lux', 'nexo', 'onyx', 'zeph', 'kron', 'vex', 'jinx',
  'kai', 'rai', 'zor', 'zer', 'vor', 'kor', 'ren', 'fen', 'prism', 'cipher',
  'nexus', 'core', 'edge', 'nova', 'orb', 'mist', 'fog', 'dew', 'coal', 'steel',
  'iron', 'gold', 'silver', 'bronze', 'rust', 'moss', 'vine', 'thorn', 'claw', 'fang',
  'horn', 'mane', 'tail', 'wing', 'beak', 'fin', 'scale', 'fur', 'hide', 'skin',
  'bone', 'skull', 'rib', 'vein', 'cell', 'atom', 'ion', 'rift', 'peak', 'vale',
  'cliff', 'dune', 'marsh', 'bog', 'wood', 'forest', 'grove', 'field', 'plain', 'glade',
  'river', 'brook', 'lake', 'pond', 'sea', 'bay', 'arch', 'gate', 'door', 'path',
  'road', 'way', 'trail', 'route', 'orbit', 'comet', 'planet', 'nebula', 'cosmos', 'zenith',
  'karma', 'yoga', 'chi', 'flint', 'quartz', 'jade', 'amber', 'opal', 'ruby', 'sapphire',
  'emerald', 'pearl', 'jet', 'coral', 'ivory', 'blade', 'shield', 'spear', 'arrow', 'bow',
  'axe', 'hammer', 'mace', 'whip', 'chain', 'rope', 'loop', 'coil', 'spiral', 'grid',
  'matrix', 'stack', 'list', 'tree', 'node', 'root', 'seed', 'bud', 'flower', 'stem',
  'honey', 'wax', 'hive', 'nest', 'den', 'lair', 'cave', 'shell', 'meta', 'anti',
  'micro', 'macro', 'mega', 'nano', 'pixel', 'bit', 'byte', 'data', 'code', 'logic',
  'proof', 'query', 'seek', 'scan', 'build', 'make', 'craft', 'mend', 'fix', 'tweak',
  'tune', 'focus', 'blur', 'tint', 'hue', 'tone', 'tilt', 'shift', 'slide', 'glide',
  'soar', 'float', 'sink', 'dive', 'leap', 'jump', 'hop', 'skip', 'run', 'dash',
  'jog', 'walk', 'roam', 'cruise', 'slip', 'snap', 'click', 'tap', 'push', 'pull',
  'lift', 'drop', 'grab', 'hold', 'free', 'lock', 'key', 'pin', 'bolt', 'hook',
  'ring', 'disc', 'wheel', 'cog', 'gear', 'spring', 'lever', 'drill', 'saw', 'file',
  'grind', 'polish', 'wax', 'paint', 'ink', 'dye', 'paper', 'clay', 'chalk', 'graphite',
  'russia', 'usa', 'canada', 'india', 'japan', 'china', 'korea', 'germany', 'france', 'spain',
  'italy', 'poland', 'sweden', 'norway', 'egypt', 'brazil', 'mexico', 'turkey', 'greece', 'israel',
  'moscow', 'tokyo', 'delhi', 'paris', 'london', 'berlin', 'rome', 'warsaw', 'stockholm', 'oslo',
  'cairo', 'seoul', 'pekin', 'doha', 'dubai', 'venice', 'minsk', 'kyiv', 'praha', 'vienna',
  'athens', 'lisbon', 'madrid', 'amsterdam', 'brussels', 'dublin', 'helsinki', 'riga', 'vilnius', 'tallinn',
  'red', 'blue', 'green', 'black', 'white', 'gray', 'pink', 'cyan', 'lime', 'teal',
  'navy', 'gold', 'silver', 'bronze', 'plum', 'olive', 'ruby', 'amber', 'coral', 'ivory',
  'bone', 'sand', 'snow', 'coal', 'rust', 'moss', 'sage', 'mint', 'rose', 'lilac',
  'desert', 'forest', 'ocean', 'river', 'mountain', 'valley', 'canyon', 'island', 'coast', 'shore',
  'field', 'plain', 'meadow', 'swamp', 'jungle', 'arctic', 'tundra', 'glacier', 'volcano', 'crater',
  'cow', 'dog', 'cat', 'rat', 'pig', 'hen', 'duck', 'goat', 'sheep', 'deer',
  'elk', 'moose', 'hare', 'wolf', 'fox', 'bear', 'lion', 'tiger', 'lynx', 'puma',
  'zebra', 'giraffe', 'hippo', 'rhino', 'whale', 'shark', 'dolphin', 'orca', 'seal', 'otter',
  'eagle', 'hawk', 'falcon', 'owl', 'raven', 'crow', 'swan', 'goose', 'heron', 'stork',
  'ant', 'bee', 'wasp', 'fly', 'bug', 'spider', 'moth', 'worm', 'slug', 'snail',
  'frog', 'toad', 'newt', 'lizard', 'snake', 'viper', 'cobra', 'gecko', 'chameleon', 'turtle',
  'batman', 'superman', 'spiderman', 'wolverine', 'cyclops', 'storm', 'flash', 'arrow', 'robin', 'joker',
  'bane', 'deadpool', 'thanos', 'hulk', 'thor', 'loki', 'odin', 'zeus', 'hermes', 'athena',
  'apple', 'google', 'amazon', 'tesla', 'samsung', 'sony', 'nokia', 'ford', 'bmw', 'audi',
  'nike', 'adidas', 'puma', 'cola', 'pepsi', 'starbucks', 'shell', 'nasa', 'spacex', 'oracle',
  'riot', 'valve', 'blizzard', 'epic', 'unity', 'ea', 'ubisoft', 'bethesda', 'sega', 'atari',
  'sonic', 'mario', 'luigi', 'zelda', 'link', 'samus', 'kirby', 'metroid', 'pokemon', 'pikachu',
  'crash', 'spyro', 'cloud', 'tifa', 'aerith', 'sephiroth', 'kratos', 'atreus', 'alan', 'max',
  'leo', 'rex', 'max', 'ace', 'jax', 'kai', 'ray', 'roy', 'ian', 'eli',
  'ava', 'mia', 'lea', 'zoe', 'eva', 'ida', 'amy', 'joy', 'bella', 'luna',
  'nova', 'iris', 'rose', 'lily', 'ruby', 'jade', 'opal', 'pearl', 'daisy', 'violet',
  'ash', 'jet', 'onyx', 'steel', 'flint', 'quartz', 'slate', 'basalt', 'granite', 'marble',
  'cube', 'sphere', 'cone', 'pyramid', 'cylinder', 'prism', 'wedge', 'orb', 'disc', 'ring',
  'king', 'queen', 'knight', 'bishop', 'rook', 'pawn', 'ace', 'jack', 'joker', 'deuce',
  'alpha', 'beta', 'gamma', 'delta', 'sigma', 'omega', 'theta', 'lambda', 'zeta', 'pi',
  'plus', 'minus', 'times', 'divide', 'equal', 'sum', 'product', 'factor', 'prime', 'logic',
  'true', 'false', 'null', 'void', 'zero', 'one', 'two', 'six', 'ten', 'max',
  'min', 'mid', 'top', 'bot', 'end', 'far', 'near', 'high', 'low', 'deep',
  'wide', 'thin', 'thick', 'long', 'short', 'fast', 'slow', 'hard', 'soft', 'warm',
  'cold', 'hot', 'cool', 'calm', 'wild', 'kind', 'bold', 'wise', 'fool', 'sage',
  'echo', 'pulse', 'surge', 'drift', 'flow', 'flux', 'wave', 'tide', 'swing', 'spin',
  'turn', 'shift', 'slide', 'glide', 'float', 'sink', 'rise', 'fall', 'drop', 'lift',
  'dash', 'rush', 'crash', 'smash', 'bash', 'clash', 'slash', 'cut', 'stab', 'punch',
  'kick', 'jump', 'leap', 'hop', 'skip', 'run', 'jog', 'walk', 'march', 'creep',
  'fade', 'blur', 'glow', 'gleam', 'shine', 'beam', 'ray', 'light', 'flare', 'spark',
  'ember', 'flame', 'blaze', 'inferno', 'torch', 'candle', 'lantern', 'lamp', 'bulb', 'led',
  'chip', 'disk', 'card', 'port', 'plug', 'socket', 'wire', 'cable', 'fiber', 'node',
  'link', 'chain', 'web', 'net', 'mesh', 'grid', 'array', 'set', 'map', 'list',
  'book', 'page', 'word', 'text', 'font', 'type', 'code', 'script', 'file', 'data',
  'time', 'date', 'year', 'month', 'week', 'day', 'hour', 'min', 'sec', 'now',
  'past', 'future', 'present', 'moment', 'epoch', 'era', 'age', 'eon', 'dawn', 'dusk',
  'wind', 'rain', 'snow', 'hail', 'sleet', 'mist', 'fog', 'dew', 'frost', 'ice',
  'fire', 'earth', 'water', 'air', 'void', 'chaos', 'order', 'light', 'dark', 'mind'
];

function generateNickname() {
  return NICKNAMES[Math.floor(Math.random() * NICKNAMES.length)];
}

async function getUniqueNickname(maxAttempts = 20) {
  for (let attempts = 0; attempts < maxAttempts; attempts++) {
    const nickname = generateNickname();
    
    try {
      const existing = await pool.query(
        'SELECT id FROM users WHERE nickname = $1', 
        [nickname]
      );
      
      if (existing.rows.length === 0) {
        return nickname;
      }
    } catch (error) {
      console.error('Error checking nickname availability:', error);
    }
  }
  
  throw new Error('Could not generate unique nickname');
}

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid or expired token' });
    }
    req.user = user;
    next();
  });
}

app.post('/api/register', async (req, res) => {
  const { pin } = req.body;

  if (!pin || pin.length < 4 || pin.length > 6 || !/^\d+$/.test(pin)) {
    return res.status(400).json({ error: 'PIN must be 4-6 digits' });
  }

  try {
    const nickname = await getUniqueNickname();
    const pinHash = await bcrypt.hash(pin, SALT_ROUNDS);

    const result = await pool.query(
      'INSERT INTO users (nickname, pin_hash, created_at, last_seen) VALUES ($1, $2, NOW(), NOW()) RETURNING id, nickname, created_at',
      [nickname, pinHash]
    );

    const user = result.rows[0];
    const token = jwt.sign({ userId: user.id, nickname: user.nickname }, JWT_SECRET, { expiresIn: '30d' });

    res.status(201).json({
      success: true,
      user: {
        id: user.id,
        nickname: user.nickname,
        created_at: user.created_at
      },
      token
    });

  } catch (error) {
    console.error('Registration error:', error);
    
    if (error.message === 'Could not generate unique nickname') {
      return res.status(500).json({ error: 'Could not generate unique nickname. Please try again.' });
    }
    
    res.status(500).json({ error: 'Registration failed' });
  }
});

app.post('/api/users/public-key', authenticateToken, async (req, res) => {
  const { publicKey } = req.body;

  if (!publicKey) {
    return res.status(400).json({ error: 'Public key required' });
  }

  try {
    await pool.query(
      'UPDATE users SET public_key = $1 WHERE id = $2',
      [publicKey, req.user.userId]
    );

    res.json({ success: true });
  } catch (error) {
    console.error('Save public key error:', error);
    res.status(500).json({ error: 'Failed to save public key' });
  }
});

app.get('/api/users/:userId/public-key', authenticateToken, async (req, res) => {
  const { userId } = req.params;

  try {
    const result = await pool.query(
      'SELECT public_key FROM users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({
      success: true,
      publicKey: result.rows[0].public_key
    });
  } catch (error) {
    console.error('Get public key error:', error);
    res.status(500).json({ error: 'Failed to get public key' });
  }
});

app.post('/api/login', async (req, res) => {
  const { nickname, pin } = req.body;

  if (!nickname || !pin) {
    return res.status(400).json({ error: 'Nickname and PIN required' });
  }

  try {
    const result = await pool.query('SELECT * FROM users WHERE nickname = $1', [nickname]);

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid nickname or PIN' });
    }

    const user = result.rows[0];
    const validPin = await bcrypt.compare(pin, user.pin_hash);

    if (!validPin) {
      return res.status(401).json({ error: 'Invalid nickname or PIN' });
    }

    await pool.query('UPDATE users SET last_seen = NOW() WHERE id = $1', [user.id]);

    const token = jwt.sign({ userId: user.id, nickname: user.nickname }, JWT_SECRET, { expiresIn: '30d' });

    res.json({
      success: true,
      user: {
        id: user.id,
        nickname: user.nickname,
        created_at: user.created_at
      },
      token
    });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

app.get('/api/users/search', authenticateToken, async (req, res) => {
  const { q } = req.query;

  if (!q || q.length < 2) {
    return res.status(400).json({ error: 'Search query must be at least 2 characters' });
  }

  try {
    const result = await pool.query(
      'SELECT id, nickname, created_at, last_seen FROM users WHERE nickname ILIKE $1 AND id != $2 LIMIT 20',
      [`%${q}%`, req.user.userId]
    );

    res.json({
      success: true,
      users: result.rows
    });

  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({ error: 'Search failed' });
  }
});

app.post('/api/chats/start', authenticateToken, async (req, res) => {
  const { targetUserId } = req.body;

  if (!targetUserId) {
    return res.status(400).json({ error: 'Target user ID required' });
  }

  if (targetUserId === req.user.userId) {
    return res.status(400).json({ error: 'Cannot chat with yourself' });
  }

  try {
    const userCheck = await pool.query('SELECT id, nickname FROM users WHERE id = $1', [targetUserId]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const existingChat = await pool.query(
      `SELECT c.*, 
        CASE 
          WHEN c.user1_id = $1 THEN u2.nickname 
          ELSE u1.nickname 
        END as partner_nickname,
        CASE 
          WHEN c.user1_id = $1 THEN c.user2_id 
          ELSE c.user1_id 
        END as partner_id
       FROM chats c
       JOIN users u1 ON c.user1_id = u1.id
       JOIN users u2 ON c.user2_id = u2.id
       WHERE (c.user1_id = $1 AND c.user2_id = $2) OR (c.user1_id = $2 AND c.user2_id = $1)`,
      [req.user.userId, targetUserId]
    );

    if (existingChat.rows.length > 0) {
      return res.json({
        success: true,
        chat: existingChat.rows[0]
      });
    }

    const newChat = await pool.query(
      `INSERT INTO chats (user1_id, user2_id, created_at) 
       VALUES ($1, $2, NOW()) 
       RETURNING *`,
      [req.user.userId, targetUserId]
    );

    const chat = newChat.rows[0];

    res.status(201).json({
      success: true,
      chat: {
        ...chat,
        partner_nickname: userCheck.rows[0].nickname,
        partner_id: targetUserId
      }
    });

  } catch (error) {
    console.error('Start chat error:', error);
    res.status(500).json({ error: 'Failed to start chat' });
  }
});

// Упрощенная версия эндпоинта для получения чатов (работает без read_at)
app.get('/api/chats', authenticateToken, async (req, res) => {
  try {
    console.log(`[DEBUG] Запрос чатов для пользователя ${req.user.userId} (${req.user.nickname})`);
    
    // 1. Получаем базовую информацию о чатах
    const chatsResult = await pool.query(
      `SELECT 
        c.*,
        CASE 
          WHEN c.user1_id = $1 THEN u2.nickname 
          ELSE u1.nickname 
        END as partner_nickname,
        CASE 
          WHEN c.user1_id = $1 THEN c.user2_id 
          ELSE c.user1_id 
        END as partner_id,
        CASE 
          WHEN c.user1_id = $1 THEN u2.last_seen 
          ELSE u1.last_seen 
        END as partner_last_seen
       FROM chats c
       JOIN users u1 ON c.user1_id = u1.id
       JOIN users u2 ON c.user2_id = u2.id
       WHERE c.user1_id = $1 OR c.user2_id = $1`,
      [req.user.userId]
    );
    
    console.log(`[DEBUG] Найдено ${chatsResult.rows.length} базовых чатов`);
    
    if (chatsResult.rows.length === 0) {
      console.log(`[DEBUG] У пользователя ${req.user.userId} нет чатов`);
      return res.json({
        success: true,
        chats: []
      });
    }
    
    // 2. Для каждого чата получаем детали
    const chatsWithDetails = [];
    
    for (const chat of chatsResult.rows) {
      try {
        // Последнее сообщение
        const lastMessageResult = await pool.query(
          `SELECT content, timestamp, sender_id 
           FROM messages 
           WHERE chat_id = $1 AND is_deleted = false 
           ORDER BY timestamp DESC 
           LIMIT 1`,
          [chat.id]
        );
        
        // Считаем ВСЕ сообщения от собеседника как "непрочитанные" 
        // (так как колонки read_at может не быть)
        const messagesFromPartner = await pool.query(
          `SELECT COUNT(*) as count 
           FROM messages 
           WHERE chat_id = $1 
             AND is_deleted = false 
             AND sender_id != $2`,
          [chat.id, req.user.userId]
        );
        
        const chatWithDetails = {
          ...chat,
          last_message: lastMessageResult.rows[0]?.content || null,
          last_message_time: lastMessageResult.rows[0]?.timestamp || null,
          last_message_sender_id: lastMessageResult.rows[0]?.sender_id || null,
          unread_count: parseInt(messagesFromPartner.rows[0]?.count || 0)
        };
        
        chatsWithDetails.push(chatWithDetails);
        
        console.log(`[DEBUG] Чат ${chat.id}: партнер=${chat.partner_nickname}, сообщений=${messagesFromPartner.rows[0]?.count || 0}`);
        
      } catch (error) {
        console.error(`[ERROR] Ошибка при обработке чата ${chat.id}:`, error);
        // Добавляем чат без деталей
        chatsWithDetails.push({
          ...chat,
          last_message: null,
          last_message_time: null,
          last_message_sender_id: null,
          unread_count: 0
        });
      }
    }
    
    // Сортируем по времени последнего сообщения
    chatsWithDetails.sort((a, b) => {
      const timeA = a.last_message_time ? new Date(a.last_message_time) : new Date(0);
      const timeB = b.last_message_time ? new Date(b.last_message_time) : new Date(0);
      return timeB - timeA;
    });
    
    console.log(`[DEBUG] Возвращаем ${chatsWithDetails.length} чатов`);
    
    res.json({
      success: true,
      chats: chatsWithDetails
    });
    
  } catch (error) {
    console.error('[ERROR] Get chats error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to get chats',
      details: error.message 
    });
  }
});

app.get('/api/chats/:chatId/messages', authenticateToken, async (req, res) => {
  const { chatId } = req.params;
  const { limit = 50, before } = req.query;

  try {
    const chatCheck = await pool.query(
      'SELECT * FROM chats WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)',
      [chatId, req.user.userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied to this chat' });
    }

    let query = `
      SELECT m.*, u.nickname as sender_nickname
      FROM messages m
      JOIN users u ON m.sender_id = u.id
      WHERE m.chat_id = $1 AND m.is_deleted = false
    `;
    const params = [chatId];

    if (before) {
      query += ` AND m.timestamp < $${params.length + 1}`;
      params.push(before);
    }

    query += ` ORDER BY m.timestamp DESC LIMIT $${params.length + 1}`;
    params.push(parseInt(limit));

    const result = await pool.query(query, params);

    res.json({
      success: true,
      messages: result.rows.reverse()
    });

  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Failed to get messages' });
  }
});

app.delete('/api/messages/:messageId', authenticateToken, async (req, res) => {
  const { messageId } = req.params;

  try {
    const result = await pool.query(
      'UPDATE messages SET is_deleted = true WHERE id = $1 AND sender_id = $2 RETURNING *',
      [messageId, req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Message not found or access denied' });
    }

    const message = result.rows[0];
    io.to(`chat_${message.chat_id}`).emit('message_deleted', {
      messageId: message.id,
      chatId: message.chat_id
    });

    res.json({
      success: true,
      message: 'Message deleted'
    });

  } catch (error) {
    console.error('Delete message error:', error);
    res.status(500).json({ error: 'Failed to delete message' });
  }
});

app.delete('/api/chats/:chatId', authenticateToken, async (req, res) => {
  const { chatId } = req.params;

  try {
    const chatCheck = await pool.query(
      'SELECT * FROM chats WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)',
      [chatId, req.user.userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied to this chat' });
    }

    const chatInfo = await pool.query(
      `SELECT user1_id, user2_id FROM chats WHERE id = $1`,
      [chatId]
    );

    await pool.query('DELETE FROM messages WHERE chat_id = $1', [chatId]);
    await pool.query('DELETE FROM chats WHERE id = $1', [chatId]);

    const chat = chatInfo.rows[0];
    io.to(`chat_${chatId}`).emit('chat_deleted', { 
      chatId,
      deletedBy: req.user.userId 
    });

    if (chat.user1_id) {
      const socketId1 = onlineUsers.get(chat.user1_id);
      if (socketId1) {
        io.to(socketId1).emit('chat_update', { 
          type: 'deleted',
          chatId 
        });
      }
    }
    
    if (chat.user2_id) {
      const socketId2 = onlineUsers.get(chat.user2_id);
      if (socketId2) {
        io.to(socketId2).emit('chat_update', { 
          type: 'deleted',
          chatId 
        });
      }
    }

    res.json({
      success: true,
      message: 'Chat deleted'
    });

  } catch (error) {
    console.error('Delete chat error:', error);
    res.status(500).json({ error: 'Failed to delete chat' });
  }
});

app.post('/api/chats/:chatId/clear', authenticateToken, async (req, res) => {
  const { chatId } = req.params;

  try {
    const chatCheck = await pool.query(
      'SELECT * FROM chats WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)',
      [chatId, req.user.userId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Access denied to this chat' });
    }

    const chatInfo = await pool.query(
      `SELECT user1_id, user2_id FROM chats WHERE id = $1`,
      [chatId]
    );

    await pool.query('DELETE FROM messages WHERE chat_id = $1', [chatId]);

    const chat = chatInfo.rows[0];
    io.to(`chat_${chatId}`).emit('messages_cleared', { 
      chatId,
      clearedBy: req.user.userId 
    });

    if (chat.user1_id) {
      const socketId1 = onlineUsers.get(chat.user1_id);
      if (socketId1) {
        io.to(socketId1).emit('chat_update', { 
          type: 'cleared',
          chatId 
        });
      }
    }
    
    if (chat.user2_id) {
      const socketId2 = onlineUsers.get(chat.user2_id);
      if (socketId2) {
        io.to(socketId2).emit('chat_update', { 
          type: 'cleared',
          chatId 
        });
      }
    }

    res.json({
      success: true,
      message: 'Messages cleared'
    });

  } catch (error) {
    console.error('Clear messages error:', error);
    res.status(500).json({ error: 'Failed to clear messages' });
  }
});

const onlineUsers = new Map();

io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  
  if (!token) {
    return next(new Error('Authentication error'));
  }

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) {
      return next(new Error('Authentication error'));
    }
    socket.userId = decoded.userId;
    socket.nickname = decoded.nickname;
    next();
  });
});

io.on('connection', async (socket) => {
  console.log(`User connected: ${socket.nickname} (${socket.userId})`);

  onlineUsers.set(socket.userId, socket.id);
  
  await pool.query('UPDATE users SET last_seen = NOW() WHERE id = $1', [socket.userId]);

  try {
    const chats = await pool.query(
      'SELECT id FROM chats WHERE user1_id = $1 OR user2_id = $1',
      [socket.userId]
    );
    
    chats.rows.forEach(chat => {
      socket.join(`chat_${chat.id}`);
    });
  } catch (error) {
    console.error('Error joining chat rooms:', error);
  }

  broadcastUserStatus(socket.userId, true);

  socket.on('send_message', async (data) => {
    const { chatId, content, encryptedKeys } = data;
  
    try {
      const chatCheck = await pool.query(
        'SELECT * FROM chats WHERE id = $1 AND (user1_id = $2 OR user2_id = $2)',
        [chatId, socket.userId]
      );
  
      if (chatCheck.rows.length === 0) {
        return socket.emit('error', { message: 'Access denied to this chat' });
      }
  
      const result = await pool.query(
        'INSERT INTO messages (chat_id, sender_id, content, encrypted_keys, timestamp, is_deleted) VALUES ($1, $2, $3, $4, NOW(), false) RETURNING *',
        [chatId, socket.userId, content, JSON.stringify(encryptedKeys || {})]
      );
  
      const message = {
        ...result.rows[0],
        sender_nickname: socket.nickname
      };
  
      io.to(`chat_${chatId}`).emit('new_message', message);

    } catch (error) {
      console.error('Send message error:', error);
      socket.emit('error', { message: 'Failed to send message' });
    }
  });

  socket.on('call_user', async (data) => {
    const { targetUserId, offer } = data;

    const targetSocketId = onlineUsers.get(targetUserId);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('incoming_call', {
        from: socket.userId,
        fromNickname: socket.nickname,
        offer
      });
    } else {
      socket.emit('call_failed', { message: 'User is offline' });
    }
  });

  socket.on('answer_call', (data) => {
    const { targetUserId, answer } = data;
    const targetSocketId = onlineUsers.get(targetUserId);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('call_answered', {
        from: socket.userId,
        answer
      });
    }
  });

  socket.on('ice_candidate', (data) => {
    const { targetUserId, candidate } = data;
    const targetSocketId = onlineUsers.get(targetUserId);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('ice_candidate', {
        from: socket.userId,
        candidate
      });
    }
  });

  socket.on('end_call', (data) => {
    const { targetUserId } = data;
    const targetSocketId = onlineUsers.get(targetUserId);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('call_ended', {
        from: socket.userId
      });
    }
  });

  socket.on('get_chats', async () => {
    try {
      const chats = await pool.query(
        `SELECT c.*, 
          CASE 
            WHEN c.user1_id = $1 THEN u2.nickname 
            ELSE u1.nickname 
          END as partner_nickname,
          CASE 
            WHEN c.user1_id = $1 THEN c.user2_id 
            ELSE c.user1_id 
          END as partner_id,
          m.content as last_message,
          m.timestamp as last_message_time
         FROM chats c
         JOIN users u1 ON c.user1_id = u1.id
         JOIN users u2 ON c.user2_id = u2.id
         LEFT JOIN LATERAL (
           SELECT content, timestamp 
           FROM messages 
           WHERE chat_id = c.id AND is_deleted = false 
           ORDER BY timestamp DESC 
           LIMIT 1
         ) m ON true
         WHERE c.user1_id = $1 OR c.user2_id = $1
         ORDER BY COALESCE(m.timestamp, c.created_at) DESC`,
        [socket.userId]
      );

      socket.emit('chats_updated', { chats: chats.rows });
    } catch (error) {
      console.error('Error getting chats:', error);
    }
  });

  socket.on('disconnect', async () => {
    console.log(`User disconnected: ${socket.nickname} (${socket.userId})`);
    
    onlineUsers.delete(socket.userId);
    
    await pool.query('UPDATE users SET last_seen = NOW() WHERE id = $1', [socket.userId]);
    
    broadcastUserStatus(socket.userId, false);
  });
});

async function broadcastUserStatus(userId, isOnline) {
  try {
    const chats = await pool.query(
      `SELECT id, 
        CASE WHEN user1_id = $1 THEN user2_id ELSE user1_id END as other_user_id
       FROM chats 
       WHERE user1_id = $1 OR user2_id = $1`,
      [userId]
    );

    chats.rows.forEach(chat => {
      const contactSocketId = onlineUsers.get(chat.other_user_id);
      if (contactSocketId) {
        io.to(contactSocketId).emit('user_status_changed', {
          userId,
          isOnline,
          lastSeen: isOnline ? null : new Date()
        });
      }
    });
  } catch (error) {
    console.error('Error broadcasting user status:', error);
  }
}

// Добавляем отладочный эндпоинт для проверки данных
app.get('/api/debug/test', authenticateToken, async (req, res) => {
  try {
    console.log(`=== DEBUG TEST для пользователя ${req.user.userId} ===`);
    
    // Проверяем таблицы
    const tables = await pool.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
    );
    
    console.log('Таблицы в БД:', tables.rows.map(r => r.table_name));
    
    // Проверяем наличие чатов
    const chats = await pool.query(
      'SELECT * FROM chats WHERE user1_id = $1 OR user2_id = $1',
      [req.user.userId]
    );
    
    console.log(`Чаты пользователя: ${chats.rows.length}`);
    
    // Для каждого чата проверяем сообщения
    for (const chat of chats.rows) {
      const messages = await pool.query(
        'SELECT COUNT(*) as count FROM messages WHERE chat_id = $1',
        [chat.id]
      );
      console.log(`Чат ${chat.id}: ${messages.rows[0].count} сообщений`);
    }
    
    res.json({
      success: true,
      tables: tables.rows.map(r => r.table_name),
      user_chats: chats.rows.length,
      user_id: req.user.userId
    });
    
  } catch (error) {
    console.error('Debug test error:', error);
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3000;

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});