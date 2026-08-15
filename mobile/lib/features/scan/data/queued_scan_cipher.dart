import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/private_local_store.dart';

class QueuedScanCipher {
  QueuedScanCipher(this._privateStore);

  static const _keyName = 'queued_scan_aes_key_v1';
  static const _formatVersion = 1;

  final PrivateLocalStore _privateStore;
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<List<int>> encrypt(List<int> clearBytes) async {
    final box = await _algorithm.encrypt(
      clearBytes,
      secretKey: await _secretKey(),
    );
    return <int>[
      _formatVersion,
      box.nonce.length,
      box.mac.bytes.length,
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ];
  }

  Future<List<int>> decrypt(List<int> encryptedBytes) async {
    if (encryptedBytes.length < 4 || encryptedBytes.first != _formatVersion) {
      throw const ApiException(
        code: 'SCAN_QUEUE_DECRYPT_FAILED',
        message: 'A saved scan could not be opened securely',
      );
    }
    final nonceLength = encryptedBytes[1];
    final macLength = encryptedBytes[2];
    final payloadStart = 3 + nonceLength + macLength;
    if (nonceLength == 0 ||
        macLength == 0 ||
        payloadStart >= encryptedBytes.length) {
      throw const ApiException(
        code: 'SCAN_QUEUE_DECRYPT_FAILED',
        message: 'A saved scan could not be opened securely',
      );
    }
    final nonce = encryptedBytes.sublist(3, 3 + nonceLength);
    final macStart = 3 + nonceLength;
    final mac = encryptedBytes.sublist(macStart, macStart + macLength);
    final cipherText = encryptedBytes.sublist(payloadStart);
    try {
      return await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: await _secretKey(),
      );
    } on SecretBoxAuthenticationError {
      throw const ApiException(
        code: 'SCAN_QUEUE_DECRYPT_FAILED',
        message: 'A saved scan could not be opened securely',
      );
    }
  }

  Future<SecretKey> _secretKey() async {
    final existing = await _privateStore.read(_keyName);
    if (existing != null) {
      try {
        final bytes = base64Decode(existing);
        if (bytes.length == 32) return SecretKey(bytes);
      } on FormatException {
        // Replace corrupt local key material below.
      }
    }
    final key = await _algorithm.newSecretKey();
    final bytes = await key.extractBytes();
    await _privateStore.write(_keyName, base64Encode(bytes));
    return key;
  }
}

class PreparedQueuedScanImages {
  const PreparedQueuedScanImages({
    required this.paths,
    required this.temporaryDirectory,
  });

  final List<String> paths;
  final String temporaryDirectory;
}
