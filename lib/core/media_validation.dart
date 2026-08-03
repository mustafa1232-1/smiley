import 'dart:typed_data';

import 'api_client.dart';

/// Per-media-type upload ceilings, mirrored with the backend config.
const int kMaxImageBytes = 10 * 1024 * 1024; // 10 MB
const int kMaxAudioBytes = 40 * 1024 * 1024; // 40 MB
const int kMaxVideoBytes = 3 * 1024 * 1024 * 1024; // 3 GB
const int kMaxOtherBytes = 25 * 1024 * 1024; // 25 MB (e.g. PDF)

/// Returns the max allowed size for a detected content type.
int maxBytesForMime(String mimeType) {
  final type = mimeType.toLowerCase();
  if (type.startsWith('image/')) return kMaxImageBytes;
  if (type.startsWith('audio/')) return kMaxAudioBytes;
  if (type.startsWith('video/')) return kMaxVideoBytes;
  return kMaxOtherBytes;
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} غيغابايت';
  }
  return '${(bytes / 1024 / 1024).round()} ميغابايت';
}

/// Allowed upload content types, mirrored with the backend allowlist.
const Set<String> kAllowedUploadMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif',
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'audio/mpeg',
  'audio/mp4',
  'audio/aac',
  'audio/wav',
  'audio/webm',
  'audio/ogg',
  'application/pdf',
};

/// Inspects the leading bytes of [bytes] and returns the detected content type,
/// or null when the signature is not recognized. This is authoritative: it
/// prevents a disguised file (e.g. an HTML page renamed to `.png`) from being
/// uploaded under a spoofed type.
String? detectMimeType(Uint8List bytes) {
  if (bytes.length < 12) return null;

  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (_startsWith(bytes, const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return 'image/png';
  }
  if (_startsWith(bytes, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (_startsWith(bytes, const [0x25, 0x50, 0x44, 0x46])) {
    return 'application/pdf';
  }
  if (_startsWith(bytes, const [0x4F, 0x67, 0x67, 0x53])) return 'audio/ogg';

  // RIFF container: WEBP (image) or WAVE (audio).
  if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46])) {
    final riffType = _ascii(bytes, 8, 4);
    if (riffType == 'WEBP') return 'image/webp';
    if (riffType == 'WAVE') return 'audio/wav';
    return null;
  }

  // MP3: ID3 tag or MPEG audio frame sync.
  if (_startsWith(bytes, const [0x49, 0x44, 0x33])) return 'audio/mpeg';
  // AAC ADTS frame sync (checked before generic MPEG sync).
  if (bytes[0] == 0xFF && (bytes[1] == 0xF1 || bytes[1] == 0xF9)) {
    return 'audio/aac';
  }
  if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return 'audio/mpeg';

  // ISO Base Media (MP4 / QuickTime / M4A / HEIC): 'ftyp' box at offset 4.
  if (_ascii(bytes, 4, 4) == 'ftyp') {
    return _brandToMime(_ascii(bytes, 8, 4));
  }

  // Matroska / WebM (EBML): audio vs video is ambiguous from the header.
  if (_startsWith(bytes, const [0x1A, 0x45, 0xDF, 0xA3])) return 'video/webm';

  return null;
}

/// Validates size and content, returning the authoritative (sniffed) content
/// type to send to the server. Throws [ApiException] with a user-facing message
/// when the file is empty, too large, or not an allowed media type.
///
/// [declaredMimeType] is only consulted to disambiguate WebM (audio vs video),
/// which share an identical container signature.
String resolveUploadMimeType({
  required Uint8List bytes,
  required String declaredMimeType,
}) {
  if (bytes.isEmpty) {
    throw const ApiException(code: 'empty_file', message: 'الملف فارغ.');
  }

  var detected = detectMimeType(bytes);
  // WebM: keep the caller's audio/video distinction when it is a WebM type.
  if (detected == 'video/webm') {
    final declared = declaredMimeType.toLowerCase();
    if (declared == 'audio/webm') detected = 'audio/webm';
  }

  if (detected == null || !kAllowedUploadMimeTypes.contains(detected)) {
    throw const ApiException(
      code: 'unsupported_media',
      message: 'نوع الملف غير مدعوم. اختر صورة أو فيديو أو صوتاً.',
    );
  }

  final maxBytes = maxBytesForMime(detected);
  if (bytes.length > maxBytes) {
    throw ApiException(
      code: 'upload_too_large',
      message: 'حجم الملف أكبر من الحد المسموح (${_formatBytes(maxBytes)}).',
    );
  }
  return detected;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String _ascii(Uint8List bytes, int offset, int length) {
  if (bytes.length < offset + length) return '';
  return String.fromCharCodes(bytes.sublist(offset, offset + length));
}

String? _brandToMime(String brand) {
  final normalized = brand.toLowerCase();
  const heifBrands = {
    'heic',
    'heix',
    'heif',
    'mif1',
    'hevc',
    'msf1',
    'heim',
    'heis',
  };
  const mp4Brands = {
    'isom',
    'iso2',
    'iso4',
    'iso5',
    'iso6',
    'mp41',
    'mp42',
    'avc1',
    'dash',
    'cmfc',
  };

  if (heifBrands.contains(normalized)) return 'image/heic';
  if (normalized.startsWith('qt')) return 'video/quicktime';
  if (normalized.startsWith('m4a')) return 'audio/mp4';
  if (mp4Brands.contains(normalized)) return 'video/mp4';
  // Unknown ISO-BMFF brand: still a valid MP4-family container.
  return 'video/mp4';
}
