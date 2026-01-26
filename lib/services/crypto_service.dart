import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  late RSAPrivateKey _privateKey;
  late RSAPublicKey _publicKey;
  late String _publicKeyPem;
  late String _privateKeyPem;

  Future<void> loadOrGenerateKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final privateKeyString = prefs.getString('private_key');
    final publicKeyString = prefs.getString('public_key');

    if (privateKeyString != null && publicKeyString != null) {
      try {
        _privateKey = _deserializeRSAPrivateKey(privateKeyString);
        _publicKey = deserializeRSAPublicKey(publicKeyString);
        _privateKeyPem = privateKeyString;
        _publicKeyPem = publicKeyString;
      } catch (e) {
        await _generateAndSaveKeys(prefs);
      }
    } else {
      await _generateAndSaveKeys(prefs);
    }
  }

  Future<void> _generateAndSaveKeys(SharedPreferences prefs) async {
    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (_) => Random.secure().nextInt(256)))));
    
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          secureRandom));
    
    final pair = keyGen.generateKeyPair();
    _publicKey = pair.publicKey as RSAPublicKey;
    _privateKey = pair.privateKey as RSAPrivateKey;

    _publicKeyPem = _serializeRSAPublicKey(_publicKey);
    _privateKeyPem = _serializeRSAPrivateKey(_privateKey);

    await prefs.setString('private_key', _privateKeyPem);
    await prefs.setString('public_key', _publicKeyPem);
  }

  String getPublicKeyPem() => _publicKeyPem;

  String _serializeRSAPublicKey(RSAPublicKey publicKey) {
    return '${publicKey.modulus!.toRadixString(16)}:${publicKey.exponent!.toRadixString(16)}';
  }

  RSAPublicKey deserializeRSAPublicKey(String keyString) {
    final parts = keyString.split(':');
    return RSAPublicKey(
      BigInt.parse(parts[0], radix: 16),
      BigInt.parse(parts[1], radix: 16),
    );
  }

  String _serializeRSAPrivateKey(RSAPrivateKey privateKey) {
    return '${privateKey.modulus!.toRadixString(16)}:${privateKey.exponent!.toRadixString(16)}:${privateKey.p!.toRadixString(16)}:${privateKey.q!.toRadixString(16)}';
  }

  RSAPrivateKey _deserializeRSAPrivateKey(String keyString) {
    final parts = keyString.split(':');
    return RSAPrivateKey(
      BigInt.parse(parts[0], radix: 16),
      BigInt.parse(parts[1], radix: 16),
      BigInt.parse(parts[2], radix: 16),
      BigInt.parse(parts[3], radix: 16),
    );
  }

  String encryptMessage(String message, String recipientPublicKeyPem) {
    try {
      final key = enc.Key.fromSecureRandom(32); // AES session key
      final iv = enc.IV.fromSecureRandom(16); // Random IV
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(message, iv: iv).base64;

      final rsaPublicKey = deserializeRSAPublicKey(recipientPublicKeyPem);
      final rsaEncrypter = RSAEngine()
        ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));
      final encryptedKey = base64Encode(rsaEncrypter.process(key.bytes));

      return jsonEncode({
        'data': encrypted,
        'key': encryptedKey,
        'iv': iv.base64,
      });
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  Uint8List decryptAESKey(String encryptedKey) {
    try {
      final rsaDecrypter = RSAEngine()
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(_privateKey));
      return rsaDecrypter.process(base64Decode(encryptedKey));
    } catch (e) {
      throw Exception('AES key decryption failed: $e');
    }
  }

  String decryptMessage(String encryptedData, String encryptedKey, String ivBase64) {
    try {
      final rsaDecrypter = RSAEngine()
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(_privateKey));
      final key = enc.Key(rsaDecrypter.process(base64Decode(encryptedKey)));
      final iv = enc.IV.fromBase64(ivBase64);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(encryptedData, iv: iv);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }
}
