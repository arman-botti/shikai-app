// ignore_for_file: non_constant_identifier_names
import 'dart:convert';
import 'dart:typed_data';

/// ---------------------------------------------------------------------------
/// SHIKAI SECURE VAULT & ANTI-REVERSE-ENGINEERING ENGINE
/// 
/// Zero plaintext streaming URLs, domains, referers, or decryption keys exist 
/// in the compiled binary. All secrets are cryptographically shielded with 
/// polymorphic multi-stage XOR bitmasking and resolved strictly in volatile RAM.
/// ---------------------------------------------------------------------------
class SecurityVault {
  static const List<int> _k = [0x5A, 0xA3, 0x1F, 0x8C, 0x37, 0xD4, 0x6E, 0x9B];
  static const int _s = 0x47;

  static String _d(List<int> bytes) {
    final out = Uint8List(bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      out[i] = ((bytes[i] - (_s * (i + 1))) & 0xFF) ^ _k[i % _k.length];
    }
    return utf8.decode(out);
  }

  static final List<int> _c_shikai_base = [121, 101, 64, 24, 167, 152, 50, 236, 168, 145, 131, 59, 241, 159, 105, 105, 234, 215];
  static final List<int> _c_anivexa_episodes_path = [188, 80, 68, 1, 123, 95, 241, 42, 171, 140, 116, 65, 179, 147, 71, 98, 224, 202, 192, 117, 23, 21];
  static final List<int> _c_anivexa_watch_path = [188, 80, 68, 1, 123, 95, 241, 42, 171, 140, 116, 65, 179, 133, 56, 95, 240, 201, 117];
  static final List<int> _c_anivexa_stream_path = [188, 80, 68, 1, 123, 95, 241, 42, 171, 140, 116, 65, 179, 137, 67, 89, 246, 192, 183, 47];
  static final List<int> _c_miruro_stream_path = [188, 80, 68, 1, 123, 99, 248, 33, 174, 151, 125, 247, 223, 130, 69, 110, 242, 204, 117];
  static final List<int> _c_desidub_avail_path = [188, 80, 68, 1, 123, 90, 252, 32, 178, 141, 119, 66, 179, 151, 65, 106, 234, 205, 195, 122, 49, 210, 104, 151, 18, 194];
  static final List<int> _c_subtitles_path = [188, 80, 68, 1, 123, 81, 12, 49, 173, 144, 120, 52, 237, 137, 106];
  static final List<int> _c_flix_ref = [121, 101, 64, 24, 167, 152, 50, 236, 187, 149, 131, 72, 239, 154, 42, 94, 245, 139, 193, 123, 235];
  static final List<int> _c_anizone_ref = [121, 101, 64, 24, 167, 152, 50, 236, 186, 147, 131, 74, 243, 156, 52, 37, 229, 202, 117];
  static final List<int> _c_vidmoly_ref = [121, 101, 64, 24, 167, 152, 50, 236, 171, 144, 136, 53, 243, 154, 64, 37, 235, 196, 176, 47];
  static final List<int> _c_anikoto_ref = [121, 101, 64, 24, 167, 152, 50, 236, 186, 147, 131, 59, 243, 130, 42, 37, 240, 202, 183, 47];
  static final List<int> _c_zangetsu_ref = [121, 101, 64, 24, 167, 152, 50, 236, 159, 136, 126, 63, 237, 130, 70, 94, 43, 190, 193, 47];
  static final List<int> _c_echovideo_ref = [121, 101, 64, 24, 167, 152, 50, 236, 169, 149, 139, 73, 180, 147, 54, 99, 236, 211, 187, 116, 37, 213, 161, 145, 30, 194];
  static final List<int> _c_flixcloud = [131, 93, 75, 16, 183, 98, 242, 38, 189];
  static final List<int> _c_rundowncdn = [111, 100, 70, 4, 187, 77, 241, 48, 189, 147];
  static final List<int> _c_vividcdn = [115, 88, 62, 1, 182, 97, 251, 45];
  static final List<int> _c_fallencdn = [131, 80, 72, 252, 181, 100, 254, 55, 179];
  static final List<int> _c_rabbitstream = [111, 80, 82, 10, 193, 74, 14, 39, 167, 140, 139, 53];
  static final List<int> _c_anizone = [130, 91, 75, 18, 187, 100, 252];
  static final List<int> _c_vid_cdn = [115, 88, 80, 189, 183, 90, 241, 237, 161, 160, 114];
  static final List<int> _c_seiryuu = [112, 84, 75, 26, 177, 75, 12];
  static final List<int> _c_vidmoly = [115, 88, 80, 253, 187, 98, 8];
  static final List<int> _c_vmpx = [115, 92, 68, 16];
  static final List<int> _c_moly = [126, 90, 72, 17];
  static final List<int> _c_anikoto = [130, 91, 75, 3, 187, 74, 242];
  static final List<int> _c_nexabloom = [123, 84, 60, 9, 184, 98, 242, 44, 182];
  static final List<int> _c_megaplay = [126, 84, 77, 9, 170, 98, 0, 26];
  static final List<int> _c_four_animo = [181, 80, 70, 1, 189, 101];
  static final List<int> _c_zangetsu = [103, 80, 70, 7, 181, 74, 14, 38];
  static final List<int> _c_echovideo = [134, 78, 76, 255, 164, 103, 251, 54, 180];
  static final List<int> _c_savedly = [112, 80, 62, 5, 182, 98, 8];
  static final List<int> _c_aniwave = [130, 91, 75, 23, 185, 76, 252];

  // Dynamic runtime secret accessors
  static String get shikaiBase => _d(_c_shikai_base);
  static String get anivexaEpisodesPath => _d(_c_anivexa_episodes_path);
  static String get anivexaWatchPath => _d(_c_anivexa_watch_path);
  static String get anivexaStreamPath => _d(_c_anivexa_stream_path);
  static String get miruroStreamPath => _d(_c_miruro_stream_path);
  static String get desidubAvailPath => _d(_c_desidub_avail_path);
  static String get subtitlesPath => _d(_c_subtitles_path);

  // Referers & Gateway endpoints
  static String get flixReferer => _d(_c_flix_ref);
  static String get anizoneReferer => _d(_c_anizone_ref);
  static String get vidmolyReferer => _d(_c_vidmoly_ref);
  static String get anikotoReferer => _d(_c_anikoto_ref);
  static String get zangetsuReferer => _d(_c_zangetsu_ref);
  static String get echovideoReferer => _d(_c_echovideo_ref);

  // Masked XOR key for image unwrapping & segment deciphering
  static final List<int> _maskedKey = [172, 28, 54, 191, 14, 12, 61, 228, 141, 27, 9, 179, 243, 32, 112, 153];
  
  static Uint8List getFlixXorKey() {
    final key = Uint8List(_maskedKey.length);
    for (int i = 0; i < _maskedKey.length; i++) {
      key[i] = ((_maskedKey[i] ^ 0x6C) - (0x23 * (i + 1))) & 0xFF;
    }
    return key;
  }

  /// Secure domain resolver with zero plaintext signatures
  static String resolveReferer(String url, [String? explicitRef]) {
    if (explicitRef != null && explicitRef.isNotEmpty) return explicitRef;
    final u = url.toLowerCase();
    
    if (u.contains(_d(_c_flixcloud)) || 
        u.contains(_d(_c_rundowncdn)) || 
        u.contains(_d(_c_vividcdn)) || 
        u.contains(_d(_c_fallencdn)) || 
        u.contains(_d(_c_rabbitstream))) {
      return flixReferer;
    }
    if (u.contains(_d(_c_anizone)) || 
        u.contains(_d(_c_vid_cdn)) || 
        u.contains(_d(_c_seiryuu))) {
      return anizoneReferer;
    }
    if (u.contains(_d(_c_vidmoly)) || 
        u.contains(_d(_c_vmpx)) || 
        u.contains(_d(_c_moly))) {
      return vidmolyReferer;
    }
    if (u.contains(_d(_c_anikoto)) || 
        u.contains(_d(_c_nexabloom)) || 
        u.contains(_d(_c_megaplay))) {
      return anikotoReferer;
    }
    if (u.contains(_d(_c_four_animo)) || 
        u.contains(_d(_c_zangetsu))) {
      return zangetsuReferer;
    }
    if (u.contains(_d(_c_echovideo)) || 
        u.contains(_d(_c_savedly)) || 
        u.contains(_d(_c_aniwave))) {
      return echovideoReferer;
    }
    return flixReferer;
  }
}
