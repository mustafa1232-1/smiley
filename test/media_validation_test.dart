import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smiley/core/api_client.dart';
import 'package:smiley/core/media_validation.dart';

Uint8List _bytes(List<int> head, {int pad = 16}) {
  final list = <int>[...head];
  while (list.length < pad) {
    list.add(0);
  }
  return Uint8List.fromList(list);
}

void main() {
  group('detectMimeType', () {
    test('detects common image signatures', () {
      expect(detectMimeType(_bytes([0xFF, 0xD8, 0xFF])), 'image/jpeg');
      expect(
        detectMimeType(_bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        'image/png',
      );
      expect(detectMimeType(_bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), 'image/gif');
    });

    test('detects RIFF containers', () {
      // "RIFF" .... "WEBP"
      expect(
        detectMimeType(_bytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])),
        'image/webp',
      );
      // "RIFF" .... "WAVE"
      expect(
        detectMimeType(_bytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45])),
        'audio/wav',
      );
    });

    test('detects ISO-BMFF brands via ftyp box', () {
      // .... "ftyp" "isom"  -> mp4
      expect(
        detectMimeType(_bytes([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D])),
        'video/mp4',
      );
      // .... "ftyp" "heic" -> heic
      expect(
        detectMimeType(_bytes([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])),
        'image/heic',
      );
      // .... "ftyp" "M4A " -> audio/mp4
      expect(
        detectMimeType(_bytes([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20])),
        'audio/mp4',
      );
    });

    test('returns null for unknown/short content', () {
      expect(detectMimeType(_bytes([0x3C, 0x68, 0x74, 0x6D, 0x6C])), isNull); // "<html"
      expect(detectMimeType(Uint8List.fromList([0x00, 0x01])), isNull);
    });
  });

  group('resolveUploadMimeType', () {
    test('returns the sniffed type, ignoring a spoofed declaration', () {
      final png = _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(
        resolveUploadMimeType(bytes: png, declaredMimeType: 'application/x-msdownload'),
        'image/png',
      );
    });

    test('rejects a disguised html file', () {
      final html = _bytes([0x3C, 0x21, 0x44, 0x4F, 0x43, 0x54, 0x59, 0x50, 0x45]);
      expect(
        () => resolveUploadMimeType(bytes: html, declaredMimeType: 'image/png'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unsupported_media')),
      );
    });

    test('rejects empty and oversized files', () {
      expect(
        () => resolveUploadMimeType(bytes: Uint8List(0), declaredMimeType: 'image/png'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'empty_file')),
      );
      // A PNG just over the 10 MB image ceiling must be rejected.
      final huge = Uint8List(kMaxImageBytes + 1);
      huge.setRange(0, 8, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(
        () => resolveUploadMimeType(bytes: huge, declaredMimeType: 'image/png'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'upload_too_large')),
      );
    });

    test('applies per-type ceilings (audio allowed above the image limit)', () {
      // ~12 MB MP3 (over the 10 MB image cap, under the 40 MB audio cap).
      final audio = Uint8List(12 * 1024 * 1024);
      audio.setRange(0, 3, const [0x49, 0x44, 0x33]); // "ID3"
      expect(
        resolveUploadMimeType(bytes: audio, declaredMimeType: 'audio/mpeg'),
        'audio/mpeg',
      );
    });

    test('disambiguates webm audio vs video from the declared type', () {
      final webm = _bytes([0x1A, 0x45, 0xDF, 0xA3]);
      expect(resolveUploadMimeType(bytes: webm, declaredMimeType: 'video/webm'), 'video/webm');
      expect(resolveUploadMimeType(bytes: webm, declaredMimeType: 'audio/webm'), 'audio/webm');
    });
  });
}
