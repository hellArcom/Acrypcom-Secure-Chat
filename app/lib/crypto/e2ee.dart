import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class E2EEManager {
  static final _dhAlgorithm = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aesGcm = AesGcm.with256bits();
  static const String _hkdfInfo = "acrypcom_e2ee";
  static final _random = Random.secure();

  static Future<SimpleKeyPair> generateKeyPair() async {
    return await _dhAlgorithm.newKeyPair();
  }

  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> hexToBytes(String hex) {
    hex = hex.trim();
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  static Future<String> getPublicKeyHex(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return bytesToHex(publicKey.bytes);
  }

  static Future<String> getPrivateKeyHex(SimpleKeyPair keyPair) async {
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return bytesToHex(privateKeyBytes);
  }

  static Future<SimpleKeyPair> keyPairFromPrivateKeyHex(String privateKeyHex) async {
    final seed = hexToBytes(privateKeyHex);
    return await _dhAlgorithm.newKeyPairFromSeed(seed);
  }

  static SimplePublicKey publicKeyFromHex(String publicKeyHex) {
    final bytes = hexToBytes(publicKeyHex);
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  static Future<Map<String, String>> encryptMessage({
    required String plaintext,
    required String recipientPublicKeyHex,
    required String messageId,
  }) async {
    final ephemeralKeyPair = await generateKeyPair();
    final ephemeralPublicKeyHex = await getPublicKeyHex(ephemeralKeyPair);
    final recipientPublicKey = publicKeyFromHex(recipientPublicKeyHex);

    final sharedSecret = await _dhAlgorithm.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final perMessageInfo = utf8.encode("$_hkdfInfo\_$messageId");
    final sessionKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: perMessageInfo,
    );

    final plaintextBytes = utf8.encode(plaintext);
    final originalLength = plaintextBytes.length;
    final paddedLength = ((originalLength ~/ 64) + 1) * 64;
    final paddingNeeded = paddedLength - originalLength;
    final paddedBytes = List<int>.from(plaintextBytes)
      ..addAll(List.generate(paddingNeeded, (_) => _random.nextInt(256)));

    final secretBox = await _aesGcm.encrypt(
      paddedBytes,
      secretKey: sessionKey,
    );

    return {
      "ciphertext": bytesToHex(secretBox.cipherText),
      "iv": bytesToHex(secretBox.nonce),
      "mac": bytesToHex(secretBox.mac.bytes),
      "ephemeral_public_key": ephemeralPublicKeyHex,
      "message_id": messageId,
      "timestamp": DateTime.now().millisecondsSinceEpoch.toString(),
      "original_length": originalLength.toString(),
    };
  }

  static Future<String> decryptMessage({
    required String myPrivateKeyHex,
    required String senderEphemeralPublicKeyHex,
    required String ciphertextHex,
    required String ivHex,
    required String macHex,
    required String messageId,
    required int originalLength,
  }) async {
    final myKeyPair = await keyPairFromPrivateKeyHex(myPrivateKeyHex);
    final senderEphemeralPublicKey = publicKeyFromHex(senderEphemeralPublicKeyHex);

    final sharedSecret = await _dhAlgorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: senderEphemeralPublicKey,
    );

    final perMessageInfo = utf8.encode("$_hkdfInfo\_$messageId");
    final sessionKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: perMessageInfo,
    );

    final ciphertext = hexToBytes(ciphertextHex);
    final iv = hexToBytes(ivHex);
    final mac = Mac(hexToBytes(macHex));

    final decryptedBytes = await _aesGcm.decrypt(
      SecretBox(ciphertext, nonce: iv, mac: mac),
      secretKey: sessionKey,
    );

    return utf8.decode(decryptedBytes.take(originalLength).toList());
  }
}
