import 'dart:typed_data';

/// Removes the GPS block from the EXIF segment of a JPEG.
///
/// Returns a modified copy of [jpeg] with the GPS IFD pointer removed from
/// IFD0 and every byte of the GPS IFD, including values stored out of line,
/// overwritten with zeros, or null when there is no GPS data to remove. The
/// length of the file does not change and nothing else is touched.
///
/// Throws a [FormatException] if the EXIF structure is malformed or points
/// outside the file, so a caller that must not leak location can fail closed
/// instead of assuming the data was removed.
Uint8List? removeGpsFromJpeg(Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    throw const FormatException('Not a JPEG file.');
  }
  var offset = 2;
  while (offset + 4 <= jpeg.length) {
    if (jpeg[offset] != 0xFF) {
      throw const FormatException('Invalid JPEG segment marker.');
    }
    final marker = jpeg[offset + 1];
    // Start of scan: compressed data follows, no more metadata segments.
    if (marker == 0xDA || marker == 0xD9) return null;
    // Markers without a length field.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    final length = (jpeg[offset + 2] << 8) | jpeg[offset + 3];
    final end = offset + 2 + length;
    if (length < 2 || end > jpeg.length) {
      throw const FormatException('JPEG segment overruns the file.');
    }
    if (marker == 0xE1 && _isExifHeader(jpeg, offset + 4, end)) {
      final copy = Uint8List.fromList(jpeg);
      final changed = _stripGps(copy, offset + 10, end);
      return changed ? copy : null;
    }
    offset = end;
  }
  return null;
}

bool _isExifHeader(Uint8List bytes, int start, int end) =>
    start + 6 <= end &&
    bytes[start] == 0x45 && // E
    bytes[start + 1] == 0x78 && // x
    bytes[start + 2] == 0x69 && // i
    bytes[start + 3] == 0x66 && // f
    bytes[start + 4] == 0 &&
    bytes[start + 5] == 0;

/// Strips GPS from the TIFF structure in `bytes[tiff, end)`. Returns whether
/// anything changed.
bool _stripGps(Uint8List bytes, int tiff, int end) {
  if (tiff + 8 > end) throw const FormatException('EXIF is too short.');
  final bool littleEndian;
  if (bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49) {
    littleEndian = true;
  } else if (bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D) {
    littleEndian = false;
  } else {
    throw const FormatException('Unknown EXIF byte order.');
  }
  final view = ByteData.sublistView(bytes);
  int u16(int at) {
    if (at < tiff || at + 2 > end) {
      throw const FormatException('EXIF offset is out of range.');
    }
    return view.getUint16(at, littleEndian ? Endian.little : Endian.big);
  }

  int u32(int at) {
    if (at < tiff || at + 4 > end) {
      throw const FormatException('EXIF offset is out of range.');
    }
    return view.getUint32(at, littleEndian ? Endian.little : Endian.big);
  }

  final ifd0 = tiff + u32(tiff + 4);
  final count = u16(ifd0);
  final entriesEnd = ifd0 + 2 + count * 12;
  if (entriesEnd + 4 > end) {
    throw const FormatException('EXIF directory overruns its segment.');
  }

  int? gpsEntry;
  for (var i = 0; i < count; i++) {
    final entry = ifd0 + 2 + i * 12;
    if (u16(entry) == 0x8825) {
      gpsEntry = entry;
      break;
    }
  }
  if (gpsEntry == null) return false;

  // Zero the GPS IFD and the values it stores out of line.
  final gpsIfd = tiff + u32(gpsEntry + 8);
  final gpsCount = u16(gpsIfd);
  final gpsEnd = gpsIfd + 2 + gpsCount * 12 + 4;
  if (gpsEnd > end) {
    throw const FormatException('GPS directory overruns its segment.');
  }
  for (var i = 0; i < gpsCount; i++) {
    final entry = gpsIfd + 2 + i * 12;
    final size = _typeSize(u16(entry + 2)) * u32(entry + 4);
    if (size > 4) {
      final value = tiff + u32(entry + 8);
      if (value < tiff || value + size > end) {
        throw const FormatException('GPS value is out of range.');
      }
      bytes.fillRange(value, value + size, 0);
    }
  }
  bytes.fillRange(gpsIfd, gpsEnd, 0);

  // Remove the pointer from IFD0: close the gap, keeping the next-IFD offset
  // directly after the last entry, and shrink the entry count.
  bytes.setRange(gpsEntry, entriesEnd - 12 + 4, bytes, gpsEntry + 12);
  bytes.fillRange(entriesEnd - 12 + 4, entriesEnd + 4, 0);
  view.setUint16(ifd0, count - 1, littleEndian ? Endian.little : Endian.big);
  return true;
}

/// Bytes per value for the TIFF field types. Unknown types count as one byte.
int _typeSize(int type) => switch (type) {
  3 || 8 => 2, // SHORT, SSHORT
  4 || 9 || 11 => 4, // LONG, SLONG, FLOAT
  5 || 10 || 12 => 8, // RATIONAL, SRATIONAL, DOUBLE
  _ => 1, // BYTE, ASCII, SBYTE, UNDEFINED
};
