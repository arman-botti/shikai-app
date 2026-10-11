import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shikai_app/models/anilist_media.dart';
import 'package:shikai_app/models/manga_chapter.dart';

class MangaSourceInfo {
  final String id;
  final String name;
  final String category; // 'Manhwa', 'Manhua', 'Manga', 'Aggregator'
  final String status;   // 'Active', 'Unstable', 'Shutdown'
  final String baseUrl;
  final String flag;
  final String description;

  const MangaSourceInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.status,
    required this.baseUrl,
    required this.flag,
    required this.description,
  });
}

/// Zero-dependency pure-Dart AES-128-CBC Decryptor for Mangago image unscrambling
class _Aes128Cbc {
  static const List<int> _invSbox = [
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d,
  ];

  static const List<int> _sbox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];

  static const List<int> _rcon = [
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
  ];

  static int _xtime(int x) => ((x << 1) ^ (((x >> 7) & 1) * 0x11b)) & 0xff;
  static int _mul(int a, int b) {
    int res = 0;
    while (b > 0) {
      if ((b & 1) != 0) res ^= a;
      a = _xtime(a);
      b >>= 1;
    }
    return res;
  }

  static Uint8List expandKey(Uint8List key) {
    final w = Uint8List(176);
    for (int i = 0; i < 16; i++) {
      w[i] = key[i];
    }
    for (int i = 4; i < 44; i++) {
      int t0 = w[(i - 1) * 4];
      int t1 = w[(i - 1) * 4 + 1];
      int t2 = w[(i - 1) * 4 + 2];
      int t3 = w[(i - 1) * 4 + 3];

      if (i % 4 == 0) {
        final tmp = t0;
        t0 = _sbox[t1] ^ _rcon[i ~/ 4];
        t1 = _sbox[t2];
        t2 = _sbox[t3];
        t3 = _sbox[tmp];
      }

      w[i * 4] = w[(i - 4) * 4] ^ t0;
      w[i * 4 + 1] = w[(i - 4) * 4 + 1] ^ t1;
      w[i * 4 + 2] = w[(i - 4) * 4 + 2] ^ t2;
      w[i * 4 + 3] = w[(i - 4) * 4 + 3] ^ t3;
    }
    return w;
  }

  static void decryptBlock(Uint8List state, Uint8List roundKeys) {
    for (int i = 0; i < 16; i++) {
      state[i] ^= roundKeys[160 + i];
    }

    for (int round = 9; round >= 1; round--) {
      final t1 = state[1], t2 = state[2], t3 = state[3];
      final t5 = state[5], t6 = state[6], t7 = state[7];
      final t9 = state[9], t10 = state[10], t11 = state[11];
      final t13 = state[13], t14 = state[14], t15 = state[15];

      state[1] = t13; state[5] = t1; state[9] = t5; state[13] = t9;
      state[2] = t10; state[6] = t14; state[10] = t2; state[14] = t6;
      state[3] = t7; state[7] = t11; state[11] = t15; state[15] = t3;

      for (int i = 0; i < 16; i++) {
        state[i] = _invSbox[state[i]];
      }

      for (int i = 0; i < 16; i++) {
        state[i] ^= roundKeys[round * 16 + i];
      }

      for (int c = 0; c < 4; c++) {
        final i = c * 4;
        final s0 = state[i], s1 = state[i + 1], s2 = state[i + 2], s3 = state[i + 3];
        state[i] = _mul(s0, 0x0e) ^ _mul(s1, 0x0b) ^ _mul(s2, 0x0d) ^ _mul(s3, 0x09);
        state[i + 1] = _mul(s0, 0x09) ^ _mul(s1, 0x0e) ^ _mul(s2, 0x0b) ^ _mul(s3, 0x0d);
        state[i + 2] = _mul(s0, 0x0d) ^ _mul(s1, 0x09) ^ _mul(s2, 0x0e) ^ _mul(s3, 0x0b);
        state[i + 3] = _mul(s0, 0x0b) ^ _mul(s1, 0x0d) ^ _mul(s2, 0x09) ^ _mul(s3, 0x0e);
      }
    }

    final t1 = state[1], t2 = state[2], t3 = state[3];
    final t5 = state[5], t6 = state[6], t7 = state[7];
    final t9 = state[9], t10 = state[10], t11 = state[11];
    final t13 = state[13], t14 = state[14], t15 = state[15];

    state[1] = t13; state[5] = t1; state[9] = t5; state[13] = t9;
    state[2] = t10; state[6] = t14; state[10] = t2; state[14] = t6;
    state[3] = t7; state[7] = t11; state[11] = t15; state[15] = t3;

    for (int i = 0; i < 16; i++) {
      state[i] = _invSbox[state[i]];
    }
    for (int i = 0; i < 16; i++) {
      state[i] ^= roundKeys[i];
    }
  }

  static Uint8List decryptCbc(Uint8List cipherText, Uint8List key, Uint8List iv) {
    final roundKeys = expandKey(key);
    final result = Uint8List(cipherText.length);
    var prevBlock = Uint8List.fromList(iv);

    for (int i = 0; i < cipherText.length; i += 16) {
      final block = Uint8List.fromList(cipherText.sublist(i, i + 16));
      final nextPrev = Uint8List.fromList(block);
      decryptBlock(block, roundKeys);
      for (int j = 0; j < 16; j++) {
        result[i + j] = block[j] ^ prevBlock[j];
      }
      prevBlock = nextPrev;
    }
    return result;
  }

  static Uint8List parseHex(String hex) {
    final list = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      list.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(list);
  }
}

class MangaService {
  static const String comickApiBaseUrl = 'https://comick-source-api.notaspider.dev';
  static const String _anilistEndpoint = 'https://graphql.anilist.co';
  static const String _mangadexBase = 'https://api.mangadex.org';

  static const String _mangaFragment = '''
    id
    title {
      romaji
      english
    }
    coverImage {
      extraLarge
      large
      medium
    }
    bannerImage
    description
    chapters
    genres
    averageScore
    status
    format
    countryOfOrigin
    type
  ''';

  /// Helper to generate strict AniList country arguments based on category
  static String _buildCountryArgs(String category) {
    final cat = category.toLowerCase().trim();
    if (cat == 'manhwa') {
      return ', countryOfOrigin: "KR"';
    } else if (cat == 'manhua') {
      return ', countryOfOrigin: "CN"';
    } else if (cat == 'manga') {
      return ', countryOfOrigin_not_in: ["KR", "CN"]';
    }
    return '';
  }

  /// Verified active scraper sources from comick-source-api
  static const List<MangaSourceInfo> allVerifiedSources = [
    // 🇰🇷 Korean Manhwa Active Sources (22)
    MangaSourceInfo(id: 'asurascan', name: 'AsuraScan', category: 'Manhwa', status: 'Active', baseUrl: 'https://asurascans.com', flag: '🇰🇷', description: 'Action, Dungeon & Hunter Manhwa'),
    MangaSourceInfo(id: 'flamecomics', name: 'FlameComics', category: 'Manhwa', status: 'Active', baseUrl: 'https://flamecomics.xyz', flag: '🇰🇷', description: 'Top-tier Action & Murim Manhwa'),
    MangaSourceInfo(id: 'raven-scans', name: 'Raven Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://ravenscans.org', flag: '🇰🇷', description: 'Eleceed, Nano Machine, Overgeared'),
    MangaSourceInfo(id: 'webtoon', name: 'WEBTOON', category: 'Manhwa', status: 'Active', baseUrl: 'https://www.webtoons.com', flag: '🇰🇷', description: 'Official Naver Webtoon Platform'),
    MangaSourceInfo(id: 'lagoonscans', name: 'LagoonScans', category: 'Manhwa', status: 'Active', baseUrl: 'https://lagoonscans.com', flag: '🇰🇷', description: 'Hunter & Leveling Webtoons'),
    MangaSourceInfo(id: 'mist-scans', name: 'Mist Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://mistscans.com', flag: '🇰🇷', description: 'Murim & Martial Arts Manhwa'),
    MangaSourceInfo(id: 'scythe-scans', name: 'Scythe Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://scythescans.com', flag: '🇰🇷', description: 'Leveling & System Webtoons'),
    MangaSourceInfo(id: 'thunderscans', name: 'Thunderscans', category: 'Manhwa', status: 'Active', baseUrl: 'https://en-thunderscans.com', flag: '🇰🇷', description: 'Action & Rebirth Webtoons'),
    MangaSourceInfo(id: 'rizz-fables', name: 'Rizz Fables', category: 'Manhwa', status: 'Active', baseUrl: 'https://rizzfables.com', flag: '🇰🇷', description: 'Hunter & Murim Webtoons'),
    MangaSourceInfo(id: 'kenscans', name: 'Kenscans', category: 'Manhwa', status: 'Active', baseUrl: 'https://kencomics.com', flag: '🇰🇷', description: 'Action & Reincarnation'),
    MangaSourceInfo(id: 'magus-manga', name: 'Magus Manga', category: 'Manhwa', status: 'Active', baseUrl: 'https://magustoon.org', flag: '🇰🇷', description: 'Magic & Academy Webtoons'),
    MangaSourceInfo(id: 'vortex-scans', name: 'Vortex Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://vortexscans.org', flag: '🇰🇷', description: 'Fast Action & Murim Releases'),
    MangaSourceInfo(id: 'elf-toon', name: 'Elf Toon', category: 'Manhwa', status: 'Active', baseUrl: 'https://elftoon.com', flag: '🇰🇷', description: 'Korean Webtoon Scans'),
    MangaSourceInfo(id: 'eva-scans', name: 'Eva Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://evascans.org', flag: '🇰🇷', description: 'Action & Fantasy Manhwa'),
    MangaSourceInfo(id: 'diva-scans', name: 'Diva Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://divatoon.com', flag: '🇰🇷', description: 'Otome & Romance Fantasy'),
    MangaSourceInfo(id: 'rokari-comics', name: 'Rokari Comics', category: 'Manhwa', status: 'Active', baseUrl: 'https://rokaricomics.com', flag: '🇰🇷', description: 'Romance & Fantasy Webtoons'),
    MangaSourceInfo(id: 'stonescape', name: 'Stonescape', category: 'Manhwa', status: 'Active', baseUrl: 'https://stonescape.xyz', flag: '🇰🇷', description: 'Korean Webtoons Scanlator'),
    MangaSourceInfo(id: 'qi-scans', name: 'Qi Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://qimanhwa.com', flag: '🇰🇷', description: 'Hunter & System Webtoons'),
    MangaSourceInfo(id: 'kuramanga', name: 'KuraManga', category: 'Manhwa', status: 'Active', baseUrl: 'https://kuramanga.com', flag: '🇰🇷', description: 'Korean Webtoon Translations'),
    MangaSourceInfo(id: 'lua-comic', name: 'Lua Comic', category: 'Manhwa', status: 'Active', baseUrl: 'https://luacomic.org', flag: '🇰🇷', description: 'Fantasy & Romance Webtoons'),
    MangaSourceInfo(id: 'violetscans', name: 'Violetscans', category: 'Manhwa', status: 'Active', baseUrl: 'https://violetmanga.com', flag: '🇰🇷', description: 'Romance & Otome Manhwa'),
    MangaSourceInfo(id: 'writers-scans', name: 'Writers Scans', category: 'Manhwa', status: 'Active', baseUrl: 'https://writerscans.com', flag: '🇰🇷', description: 'Fantasy & Action Webtoons'),

    // 🇨🇳 Chinese Manhua Active Sources (6)
    MangaSourceInfo(id: 'manhuaplus', name: 'ManhuaPlus', category: 'Manhua', status: 'Active', baseUrl: 'https://manhuaplus.top', flag: '🇨🇳', description: 'Martial Peak, Apotheosis, BTTH'),
    MangaSourceInfo(id: 'spider-scans', name: 'Spider Scans', category: 'Manhua', status: 'Active', baseUrl: 'https://spiderscans.xyz', flag: '🇨🇳', description: 'All Hail the Sect Leader, Cultivation'),
    MangaSourceInfo(id: 'yaksha-comics', name: 'Yaksha Comics', category: 'Manhua', status: 'Active', baseUrl: 'https://yakshacomics.com', flag: '🇨🇳', description: 'Netherworld Reaper, Beast Taming'),
    MangaSourceInfo(id: 'arya-scans', name: 'Arya Scans', category: 'Manhua', status: 'Active', baseUrl: 'https://brainrotcomics.com', flag: '🇨🇳', description: 'Martial Arts & Cultivation Manhua'),
    MangaSourceInfo(id: 'topmanhua', name: 'TopManhua', category: 'Manhua', status: 'Active', baseUrl: 'https://manhuatop.org', flag: '🇨🇳', description: 'Cultivation & Wuxia Aggregator'),
    MangaSourceInfo(id: 'manhuaus', name: 'ManhuaUS', category: 'Manhua', status: 'Active', baseUrl: 'https://manhuaus.com', flag: '🇨🇳', description: 'Immortal Rebirth & Urban Cultivation'),

    // 🇯🇵 Japanese Manga Active Sources (11)
    MangaSourceInfo(id: 'weebcentral', name: 'WeebCentral', category: 'Manga', status: 'Active', baseUrl: 'https://weebcentral.com', flag: '🇯🇵', description: '20,000+ Japanese Manga Archive'),
    MangaSourceInfo(id: 'mangakatana', name: 'MangaKatana', category: 'Manga', status: 'Active', baseUrl: 'https://mangakatana.com', flag: '🇯🇵', description: 'Huge Japanese Manga Catalog'),
    MangaSourceInfo(id: 'lhtranslation', name: 'LHTranslation', category: 'Manga', status: 'Active', baseUrl: 'https://lhtranslation.net', flag: '🇯🇵', description: 'Narou Web Novel & Isekai Manga'),
    MangaSourceInfo(id: 'mangasushi', name: 'Mangasushi', category: 'Manga', status: 'Active', baseUrl: 'https://mangasushi.org', flag: '🇯🇵', description: 'Japanese Fantasy & Cooking Manga'),
    MangaSourceInfo(id: 'kdt-scans', name: 'SilentQuill (KDT)', category: 'Manga', status: 'Active', baseUrl: 'https://www.silentquill.net', flag: '🇯🇵', description: 'Japanese Seinen & Isekai Manga'),
    MangaSourceInfo(id: 'kappabeast', name: 'KappaBeast', category: 'Manga', status: 'Active', baseUrl: 'https://kappabeast.com', flag: '🇯🇵', description: 'Light Novel Manga Adaptations'),
    MangaSourceInfo(id: 'ks-group-scans', name: 'KS Group', category: 'Manga', status: 'Active', baseUrl: 'https://ksgroupscans.com', flag: '🇯🇵', description: 'Fantasy & RomCom Manga'),
    MangaSourceInfo(id: 'galaxy-degen-scans', name: 'Galaxy Degen', category: 'Manga', status: 'Active', baseUrl: 'https://gdscans.com', flag: '🇯🇵', description: 'Japanese Shonen & Comedy Manga'),
    MangaSourceInfo(id: 'rd-scans', name: 'RD Scans', category: 'Manga', status: 'Active', baseUrl: 'https://rdscans.com', flag: '🇯🇵', description: 'Japanese RomCom & Ecchi Manga'),
    MangaSourceInfo(id: 'ritharscans', name: 'Ritharscans', category: 'Manga', status: 'Active', baseUrl: 'https://ritharscans.com', flag: '🇯🇵', description: 'Isekai & Reincarnated Hero Manga'),
    MangaSourceInfo(id: 'asmodeus-scans', name: 'Asmodeus Scans', category: 'Manga', status: 'Active', baseUrl: 'https://asmotoon.com', flag: '🇯🇵', description: 'Mature Japanese Manga Scans'),

    // 🌐 Multi-Origin Aggregators (13)
    MangaSourceInfo(id: 'mangago', name: 'Mangago', category: 'Aggregator', status: 'Active', baseUrl: 'https://www.mangago.zone', flag: '🌐', description: 'Massive Global Manga & Webtoons'),
    MangaSourceInfo(id: 'mangaread', name: 'MangaRead', category: 'Aggregator', status: 'Active', baseUrl: 'https://mangaread.org', flag: '🌐', description: 'High-speed Multi-origin Reader'),
    MangaSourceInfo(id: 'comix', name: 'Comix', category: 'Aggregator', status: 'Active', baseUrl: 'https://comix.to', flag: '🌐', description: 'Multi-category Comic Catalog'),
    MangaSourceInfo(id: 'atsumoe', name: 'AtsuMoe', category: 'Aggregator', status: 'Active', baseUrl: 'https://atsumoe.com', flag: '🌐', description: 'Asian Comics Aggregator'),
    MangaSourceInfo(id: 'mgeko', name: 'Mgeko', category: 'Aggregator', status: 'Active', baseUrl: 'https://mgeko.cc', flag: '🌐', description: 'Global Comics & Manga Archive'),
    MangaSourceInfo(id: 'demonicscans', name: 'DemonicScans', category: 'Aggregator', status: 'Active', baseUrl: 'https://demonicscans.org', flag: '🌐', description: 'Action Manhwa & Cultivation'),
    MangaSourceInfo(id: 'madarascans', name: 'Madarascans', category: 'Aggregator', status: 'Active', baseUrl: 'https://madarascans.com', flag: '🌐', description: 'WordPress Madara Aggregator'),
    MangaSourceInfo(id: 'mangataro', name: 'Mangataro', category: 'Aggregator', status: 'Active', baseUrl: 'https://mangataro.org', flag: '🌐', description: 'Fast Manga & Webtoon Reader'),
    MangaSourceInfo(id: 'mangayy', name: 'MangaYY', category: 'Aggregator', status: 'Active', baseUrl: 'https://mangayy.org', flag: '🌐', description: 'Multi-source Comic Library'),
    MangaSourceInfo(id: 'project-suki', name: 'Project Suki', category: 'Aggregator', status: 'Active', baseUrl: 'https://projectsuki.com', flag: '🌐', description: 'Community Multi-origin Aggregator'),
    MangaSourceInfo(id: 'athrea-scans', name: 'Athrea Scans', category: 'Aggregator', status: 'Active', baseUrl: 'https://athreascans.com', flag: '🌐', description: 'Manhwa & Cultivation Scans'),
    MangaSourceInfo(id: 'likemanga', name: 'LikeManga', category: 'Aggregator', status: 'Active', baseUrl: 'https://likemanga.io', flag: '🌐', description: 'Multi-source Webtoons Reader'),
    MangaSourceInfo(id: 'mangadex', name: 'MangaDex', category: 'Aggregator', status: 'Active', baseUrl: 'https://mangadex.org', flag: '🌐', description: 'Official Global Open-API Archive'),
  ];

  /// Get structured source objects filtered by active category
  static List<MangaSourceInfo> getActiveSources(String category) {
    final cat = category.toLowerCase().trim();
    if (cat == 'manhwa') {
      return allVerifiedSources.where((s) => s.category == 'Manhwa' || s.category == 'Aggregator').toList();
    } else if (cat == 'manhua') {
      return allVerifiedSources.where((s) => s.category == 'Manhua' || s.category == 'Aggregator').toList();
    } else if (cat == 'manga') {
      return allVerifiedSources.where((s) => s.category == 'Manga' || s.category == 'Aggregator').toList();
    }
    return allVerifiedSources;
  }

  /// Active scraper sources verified from comick-source-api for each category
  static List<String> getActiveSourceNames(String category) {
    return getActiveSources(category).map((s) => '${s.name} ${s.flag}').toList();
  }

  /// Determine priority sources to query for a category
  static List<String> getPriorityScraperIds(String category) {
    final cat = category.toLowerCase().trim();
    if (cat == 'manhwa') {
      return ['asurascan', 'mangago', 'webtoon', 'flamecomics', 'raven-scans', 'lagoonscans', 'thunderscans'];
    } else if (cat == 'manhua') {
      return ['manhuaplus', 'topmanhua', 'spider-scans', 'yaksha-comics', 'manhuaus', 'arya-scans'];
    } else if (cat == 'manga') {
      return ['weebcentral', 'mangakatana', 'mangaread', 'lhtranslation', 'mangasushi', 'kappabeast'];
    }
    // 'All' - Comprehensive mix
    return ['mangago', 'asurascan', 'weebcentral', 'mangaread', 'manhuaplus', 'webtoon'];
  }

  // --------------------------------------------------------------------------
  // COMICK-SOURCE-API MULTI-SCRAPER SEARCH ENGINE
  // --------------------------------------------------------------------------

  /// Search manga across comick-source-api scrapers based on category
  static Future<List<AnilistMedia>> searchManga(
    String search, {
    String category = 'All',
    int page = 1,
    int perPage = 20,
  }) async {
    final trimmedQuery = search.trim();
    if (trimmedQuery.isEmpty) return [];

    // 1. Primary: Query comick-source-api across classified sources
    final comickResults = await searchComickSourceApi(trimmedQuery, category: category);
    if (comickResults.isNotEmpty) {
      return comickResults;
    }

    // 2. Fallback to AniList GraphQL if comick returned empty
    final countryFilter = _buildCountryArgs(category);
    final query = '''
      query (\$search: String, \$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(search: \$search, type: MANGA, isAdult: false$countryFilter) {
            $_mangaFragment
          }
        }
      }
    ''';
    return _fetchMangaList(query, {'search': trimmedQuery, 'page': page, 'perPage': perPage});
  }

  /// High-concurrency scraper search via comick-source-api
  static Future<List<AnilistMedia>> searchComickSourceApi(
    String query, {
    String category = 'All',
  }) async {
    final sourcesToQuery = getPriorityScraperIds(category);
    final List<Future<List<AnilistMedia>>> tasks = [];

    for (final srcId in sourcesToQuery) {
      tasks.add(() async {
        try {
          final res = await http.post(
            Uri.parse('$comickApiBaseUrl/api/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, 'source': srcId}),
          ).timeout(const Duration(milliseconds: 4500));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final List<dynamic> list = data['results'] ?? [];
            final sourceName = data['source']?.toString() ?? srcId;

            return list.map((item) {
              return AnilistMedia.fromComickSearchResult(
                item as Map<String, dynamic>,
                source: sourceName,
                category: category,
              );
            }).toList();
          }
        } catch (_) {}
        return <AnilistMedia>[];
      }());
    }

    final resultsNested = await Future.wait(tasks);
    final List<AnilistMedia> combined = [];
    final Set<String> seenTitles = {};

    for (final list in resultsNested) {
      for (final item in list) {
        final norm = item.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (norm.isNotEmpty && seenTitles.add(norm)) {
          combined.add(item);
        }
      }
    }

    return combined;
  }

  /// Fetch trending manga from AniList (with optional category filter: 'All', 'Manga', 'Manhwa', 'Manhua')
  static Future<List<AnilistMedia>> getTrendingManga({String category = 'All', int page = 1, int perPage = 15}) async {
    final countryFilter = _buildCountryArgs(category);
    final query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: TRENDING_DESC, type: MANGA, isAdult: false$countryFilter) {
            $_mangaFragment
          }
        }
      }
    ''';
    return _fetchMangaList(query, {'page': page, 'perPage': perPage});
  }

  /// Fetch popular all-time manga (with optional category filter: 'All', 'Manga', 'Manhwa', 'Manhua')
  static Future<List<AnilistMedia>> getPopularManga({String category = 'All', int page = 1, int perPage = 15}) async {
    final countryFilter = _buildCountryArgs(category);
    final query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: POPULARITY_DESC, type: MANGA, isAdult: false$countryFilter) {
            $_mangaFragment
          }
        }
      }
    ''';
    return _fetchMangaList(query, {'page': page, 'perPage': perPage});
  }

  /// Fetch popular Korean Manhwa / Webtoons (STRICTLY South Korea - KR)
  static Future<List<AnilistMedia>> getPopularManhwa({int page = 1, int perPage = 15}) async {
    return getPopularManga(category: 'Manhwa', page: page, perPage: perPage);
  }

  /// Fetch popular Chinese Manhua (STRICTLY China - CN)
  static Future<List<AnilistMedia>> getPopularManhua({int page = 1, int perPage = 15}) async {
    return getPopularManga(category: 'Manhua', page: page, perPage: perPage);
  }

  /// Fetch popular Japanese Manga (STRICTLY Japan - JP)
  static Future<List<AnilistMedia>> getPopularJapaneseManga({int page = 1, int perPage = 15}) async {
    return getPopularManga(category: 'Manga', page: page, perPage: perPage);
  }

  /// Fetch top rated manga (with optional category filter: 'All', 'Manga', 'Manhwa', 'Manhua')
  static Future<List<AnilistMedia>> getTopRatedManga({String category = 'All', int page = 1, int perPage = 15}) async {
    final countryFilter = _buildCountryArgs(category);
    final query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(sort: SCORE_DESC, type: MANGA, isAdult: false$countryFilter) {
            $_mangaFragment
          }
        }
      }
    ''';
    return _fetchMangaList(query, {'page': page, 'perPage': perPage});
  }

  /// Filter manga by genre (with optional category filter)
  static Future<List<AnilistMedia>> getMangaByGenre(String genre, {String category = 'All', int page = 1, int perPage = 20}) async {
    final countryFilter = _buildCountryArgs(category);
    final query = '''
      query (\$genre: String, \$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(genre: \$genre, sort: POPULARITY_DESC, type: MANGA, isAdult: false$countryFilter) {
            $_mangaFragment
          }
        }
      }
    ''';
    return _fetchMangaList(query, {'genre': genre, 'page': page, 'perPage': perPage});
  }

  /// Fetch full details for a manga
  static Future<AnilistMedia?> getMangaDetails(int anilistId) async {
    const query = '''
      query (\$id: Int) {
        Media(id: \$id, type: MANGA) {
          $_mangaFragment
        }
      }
    ''';

    try {
      final res = await http.post(
        Uri.parse(_anilistEndpoint),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'query': query, 'variables': {'id': anilistId}}),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data']['Media'];
        if (data != null) {
          return AnilistMedia.fromJson(data);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Helper to fetch and parse AniList media list
  static Future<List<AnilistMedia>> _fetchMangaList(String query, Map<String, dynamic> variables) async {
    try {
      final response = await http.post(
        Uri.parse(_anilistEndpoint),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'query': query, 'variables': variables}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> list = data['data']?['Page']?['media'] ?? [];
        return list.map((json) {
          json['type'] = 'MANGA';
          return AnilistMedia.fromJson(json);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // --------------------------------------------------------------------------
  // HIGH-PERFORMANCE MULTI-SOURCE CHAPTER & PAGE RESOLVER
  // Primary: comick-source-api (Mangago, AsuraScan, WeebCentral, MangaRead, etc.)
  // Secondary: MangaRead direct web scraper
  // Fallback: MangaDex (Official global API)
  // --------------------------------------------------------------------------

  /// Resolves chapters for a manga using comick-source-api (with MangaRead & MangaDex fallbacks)
  static Future<List<MangaChapter>> getMangaChapters(
    String title, {
    String? englishTitle,
    String? sourceUrl,
    String? sourceId,
  }) async {
    // 1. If direct sourceUrl is present from comick-source-api search result
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      final chapters = await _fetchChaptersFromComickApi(sourceUrl, sourceId: sourceId);
      if (chapters.isNotEmpty) {
        return chapters;
      }
    }

    // 2. Query comick-source-api search by title to find scraper series URL
    final queryTitle = (englishTitle != null && englishTitle.trim().isNotEmpty) ? englishTitle : title;
    final comickResults = await searchComickSourceApi(queryTitle);
    if (comickResults.isNotEmpty && comickResults.first.sourceUrl != null) {
      final chapters = await _fetchChaptersFromComickApi(
        comickResults.first.sourceUrl!,
        sourceId: comickResults.first.sourceId,
      );
      if (chapters.isNotEmpty) {
        return chapters;
      }
    }

    // 3. Try MangaRead direct engine
    final mangaReadChapters = await _fetchChaptersFromMangaRead(title, englishTitle: englishTitle);
    if (mangaReadChapters.isNotEmpty) {
      return mangaReadChapters;
    }

    // 4. Fallback to MangaDex
    return _fetchChaptersFromMangaDex(title, englishTitle: englishTitle);
  }

  /// Call comick-source-api /api/chapters endpoint
  static Future<List<MangaChapter>> _fetchChaptersFromComickApi(
    String seriesUrl, {
    String? sourceId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$comickApiBaseUrl/api/chapters'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'url': seriesUrl,
          if (sourceId != null && sourceId.isNotEmpty) 'source': sourceId,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> list = data['chapters'] ?? [];
        final List<MangaChapter> chapters = [];

        for (final item in list) {
          final cUrl = item['url']?.toString() ?? '';
          final cNumber = item['number']?.toString() ?? '1';
          var cTitle = (item['title'] ?? '').toString().trim();
          if (cTitle.isEmpty) {
            cTitle = 'Chapter $cNumber';
          }

          chapters.add(MangaChapter(
            id: cUrl.isNotEmpty ? cUrl : (item['id']?.toString() ?? cNumber),
            chapterNumber: cNumber,
            title: cTitle,
            url: cUrl,
            source: sourceId,
          ));
        }

        if (chapters.isNotEmpty) {
          chapters.sort((a, b) {
            final double? numA = double.tryParse(a.chapterNumber);
            final double? numB = double.tryParse(b.chapterNumber);
            if (numA != null && numB != null) return numA.compareTo(numB);
            return a.chapterNumber.compareTo(b.chapterNumber);
          });
          return chapters;
        }
      }
    } catch (_) {}
    return [];
  }

  /// Resolves direct chapter panel images across sources
  static Future<List<String>> getChapterPages(
    String chapterId, {
    String? chapterUrl,
    String? source,
  }) async {
    final targetUrl = chapterUrl ?? (chapterId.startsWith('http') ? chapterId : null);

    // 1. Mangago Chapter
    if (targetUrl != null && (targetUrl.contains('mangago.zone') || targetUrl.contains('mangago.me'))) {
      final pages = await _fetchPagesFromMangago(targetUrl);
      if (pages.isNotEmpty) return pages;
    }

    // 2. AsuraScan Chapter
    if (targetUrl != null && (targetUrl.contains('asurascans.com') || targetUrl.contains('asura'))) {
      final pages = await _fetchPagesFromAsuraScan(targetUrl);
      if (pages.isNotEmpty) return pages;
    }

    // 3. WeebCentral Chapter
    if (targetUrl != null && targetUrl.contains('weebcentral.com')) {
      final pages = await _fetchPagesFromWeebCentral(targetUrl);
      if (pages.isNotEmpty) return pages;
    }

    // 4. MangaRead Chapter
    if (chapterId.startsWith('mangaread:') || (targetUrl != null && targetUrl.contains('mangaread.org'))) {
      final cleanUrl = targetUrl ?? chapterId.replaceFirst('mangaread:', '');
      final pages = await _fetchPagesFromMangaRead(cleanUrl);
      if (pages.isNotEmpty) return pages;
    }

    // 5. General generic webtoon scraper fallback
    if (targetUrl != null && targetUrl.startsWith('http')) {
      final genericPages = await _fetchGenericPages(targetUrl);
      if (genericPages.isNotEmpty) return genericPages;
    }

    // 6. Default / Fallback to MangaDex
    return _fetchPagesFromMangaDex(chapterId);
  }

  /// High-speed decryptor and image extractor for Mangago chapters
  static Future<List<String>> _fetchPagesFromMangago(String chapterUrl) async {
    try {
      final res = await http.get(
        Uri.parse(chapterUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://www.mangago.zone/',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final html = res.body;
        final match = RegExp(r'var imgsrcs\s*=\s*[\x27"]([^\x27"]+)[\x27"]').firstMatch(html);
        if (match != null) {
          final enc = match.group(1)!;
          final key = _Aes128Cbc.parseHex("e11adc3949ba59abbe56e057f20f883e");
          final iv = _Aes128Cbc.parseHex("1234567890abcdef1234567890abcdef");
          final decrypted = _Aes128Cbc.decryptCbc(base64Decode(enc), key, iv);
          final raw = utf8.decode(decrypted).replaceAll(RegExp(r'\x00+$'), '');

          final pages = raw.split(',').map((p) => p.trim()).where((p) => p.startsWith('http')).map((p) {
            // Fix Cloudflare redirect loop on iweb_ servers: use http instead of https
            if (p.contains('iweb_') && p.startsWith('https://')) {
              return p.replaceFirst('https://', 'http://');
            }
            return p;
          }).toList();

          if (pages.isNotEmpty) {
            return pages;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  /// High-speed extractor for AsuraScan chapters
  static Future<List<String>> _fetchPagesFromAsuraScan(String chapterUrl) async {
    try {
      final res = await http.get(
        Uri.parse(chapterUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://asurascans.com/',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final html = res.body;
        // Matches all CDN images from chapter json / dom
        final matches = RegExp(
          r'https://cdn\.asurascans\.com/asura-images/chapters/[^\s"<>]+',
          caseSensitive: false,
        ).allMatches(html);

        final Set<String> seen = {};
        final List<String> pages = [];
        for (final m in matches) {
          var u = m.group(0)!;
          u = u.replaceAll('&quot;', '').replaceAll(r'\"', '').replaceAll(r'\', '');
          final clean = u.split('?').first;
          if (seen.add(clean)) {
            pages.add(u);
          }
        }

        if (pages.isNotEmpty) return pages;
      }
    } catch (_) {}
    return [];
  }

  /// High-speed extractor for WeebCentral chapters
  static Future<List<String>> _fetchPagesFromWeebCentral(String chapterUrl) async {
    try {
      final idMatch = RegExp(r'/chapters/([a-zA-Z0-9]+)').firstMatch(chapterUrl);
      if (idMatch == null) return [];
      final chapterId = idMatch.group(1)!;

      final imagesEndpoint = 'https://weebcentral.com/chapters/$chapterId/images?is_prev=False&current_page=1&reading_style=long_strip';
      final res = await http.get(
        Uri.parse(imagesEndpoint),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://weebcentral.com/',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final html = res.body;
        final matches = RegExp(
          r'https://[^\s"<>]+\.(?:png|jpg|jpeg|webp)',
          caseSensitive: false,
        ).allMatches(html);

        final Set<String> seen = {};
        final List<String> pages = [];
        for (final m in matches) {
          final u = m.group(0)!;
          if (!u.contains('brand.png') && !u.contains('logo') && seen.add(u)) {
            pages.add(u);
          }
        }
        if (pages.isNotEmpty) return pages;
      }
    } catch (_) {}
    return [];
  }

  /// High-speed panel extractor for MangaRead chapters
  static Future<List<String>> _fetchPagesFromMangaRead(String chapterUrl) async {
    try {
      final res = await http.get(
        Uri.parse(chapterUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.mangaread.org/',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final html = res.body;
        final imgRegex = RegExp(
          r'<img[^>]+(?:src|data-src)="\s*([^"]+)\s*"[^>]*class="[^"]*wp-manga-chapter-img',
          caseSensitive: false,
        );

        final matches = imgRegex.allMatches(html);
        final pages = <String>[];
        for (final m in matches) {
          final url = m.group(1)!.trim();
          if (url.startsWith('http')) {
            pages.add(url);
          }
        }

        if (pages.isNotEmpty) {
          return pages;
        }

        final altRegex = RegExp(
          r'<div class="page-break[^"]*">\s*<img[^>]+(?:src|data-src)="\s*([^"]+)\s*"',
          caseSensitive: false,
        );
        for (final m in altRegex.allMatches(html)) {
          final url = m.group(1)!.trim();
          if (url.startsWith('http') && !pages.contains(url)) {
            pages.add(url);
          }
        }
        return pages;
      }
    } catch (_) {}
    return [];
  }

  /// Generic page extractor from arbitrary comic reader page HTML
  static Future<List<String>> _fetchGenericPages(String chapterUrl) async {
    try {
      final res = await http.get(
        Uri.parse(chapterUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final html = res.body;
        final matches = RegExp(
          r'<img[^>]+(?:src|data-src)="\s*(https://[^"]+\.(?:jpg|jpeg|png|webp))',
          caseSensitive: false,
        ).allMatches(html);

        final List<String> pages = [];
        final Set<String> seen = {};
        for (final m in matches) {
          final u = m.group(1)!.trim();
          if (!u.contains('logo') && !u.contains('icon') && seen.add(u)) {
            pages.add(u);
          }
        }
        return pages;
      }
    } catch (_) {}
    return [];
  }

  /// High-speed scraper for MangaRead series
  static Future<List<MangaChapter>> _fetchChaptersFromMangaRead(String title, {String? englishTitle}) async {
    final titlesToTry = <String>{
      if (englishTitle != null && englishTitle.trim().isNotEmpty) englishTitle.trim(),
      title.trim(),
      title.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim(),
    }.toList();

    for (final t in titlesToTry) {
      if (t.isEmpty) continue;
      try {
        final searchUrl = Uri.parse('https://www.mangaread.org/?s=${Uri.encodeComponent(t)}&post_type=wp-manga');
        final searchRes = await http.get(
          searchUrl,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 5));

        if (searchRes.statusCode != 200) continue;

        final searchHtml = searchRes.body;
        final titleMatches = RegExp(
          r'<div class="post-title">\s*<h3 class="h4"><a href="([^"]+)">([^<]+)</a>',
          caseSensitive: false,
        ).allMatches(searchHtml);

        if (titleMatches.isEmpty) continue;

        String mangaUrl = titleMatches.first.group(1)!;
        final cleanQuery = t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        for (final m in titleMatches) {
          final matchedTitle = m.group(2)!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (matchedTitle == cleanQuery || matchedTitle.contains(cleanQuery)) {
            mangaUrl = m.group(1)!;
            break;
          }
        }

        final mangaRes = await http.get(
          Uri.parse(mangaUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ).timeout(const Duration(seconds: 6));

        if (mangaRes.statusCode != 200) continue;

        final mangaHtml = mangaRes.body;
        final chapterRegex = RegExp(
          r'<li class="wp-manga-chapter[^"]*">(?:(?!</li>).)*?<a href="([^"]+)">\s*([^<]+)</a>',
          caseSensitive: false,
          dotAll: true,
        );

        final matches = chapterRegex.allMatches(mangaHtml);
        if (matches.isEmpty) continue;

        final List<MangaChapter> chapters = [];
        final Set<String> seenNumbers = {};

        for (final match in matches) {
          final chapUrl = match.group(1)!.trim();
          final rawTitle = match.group(2)!.trim();

          final numMatch = RegExp(r'(?:chapter|ch\.?)\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(rawTitle) ??
              RegExp(r'/chapter-(\d+(?:\.\d+)?)/?', caseSensitive: false).firstMatch(chapUrl);

          final chapNum = numMatch != null ? numMatch.group(1)! : '1';

          if (seenNumbers.add(chapNum)) {
            chapters.add(MangaChapter(
              id: 'mangaread:$chapUrl',
              chapterNumber: chapNum,
              title: rawTitle.isNotEmpty ? rawTitle : 'Chapter $chapNum',
              url: chapUrl,
              source: 'mangaread',
            ));
          }
        }

        if (chapters.isNotEmpty) {
          chapters.sort((a, b) {
            final double? numA = double.tryParse(a.chapterNumber);
            final double? numB = double.tryParse(b.chapterNumber);
            if (numA != null && numB != null) return numA.compareTo(numB);
            return a.chapterNumber.compareTo(b.chapterNumber);
          });
          return chapters;
        }
      } catch (_) {}
    }
    return [];
  }

  // --------------------------------------------------------------------------
  // MANGADEX RESOLVER (Global Free Fallback)
  // --------------------------------------------------------------------------

  /// Resolves chapters for a manga using MangaDex API
  static Future<List<MangaChapter>> _fetchChaptersFromMangaDex(String title, {String? englishTitle}) async {
    try {
      String queryTitle = englishTitle != null && englishTitle.isNotEmpty ? englishTitle : title;
      queryTitle = queryTitle.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

      String? mangadexId = await _findMangadexMangaId(queryTitle);
      if (mangadexId == null && title != queryTitle) {
        mangadexId = await _findMangadexMangaId(title);
      }

      if (mangadexId == null) {
        return [];
      }

      final feedUrl = Uri.parse(
        '$_mangadexBase/manga/$mangadexId/feed?translatedLanguage[]=en&order[chapter]=asc&limit=500',
      );

      final res = await http.get(feedUrl).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> list = data['data'] ?? [];

        final Map<String, MangaChapter> chapterMap = {};

        for (var item in list) {
          final attrs = item['attributes'] ?? {};
          final chapterNumStr = attrs['chapter'];
          if (chapterNumStr == null || chapterNumStr.toString().trim().isEmpty) continue;

          final chapterNumber = chapterNumStr.toString().trim();
          final chapterTitle = (attrs['title'] ?? '').toString().trim();
          final pagesCount = attrs['pages'] ?? 0;
          final publishAt = attrs['publishAt']?.toString();

          if (!chapterMap.containsKey(chapterNumber)) {
            chapterMap[chapterNumber] = MangaChapter(
              id: item['id'],
              chapterNumber: chapterNumber,
              title: chapterTitle,
              volume: attrs['volume']?.toString(),
              releaseDate: publishAt,
              totalPages: pagesCount,
              source: 'mangadex',
            );
          }
        }

        final chapters = chapterMap.values.toList();
        chapters.sort((a, b) {
          final double? numA = double.tryParse(a.chapterNumber);
          final double? numB = double.tryParse(b.chapterNumber);
          if (numA != null && numB != null) return numA.compareTo(numB);
          return a.chapterNumber.compareTo(b.chapterNumber);
        });

        return chapters;
      }
    } catch (_) {}
    return [];
  }

  /// Helper to search MangaDex and find manga UUID
  static Future<String?> _findMangadexMangaId(String title) async {
    try {
      final searchUrl = Uri.parse(
        '$_mangadexBase/manga?title=${Uri.encodeComponent(title)}&limit=5&includes[]=cover_art',
      );
      final res = await http.get(searchUrl).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['data'] as List<dynamic>?;
        if (list != null && list.isNotEmpty) {
          return list.first['id']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetch direct page image URLs from MangaDex
  static Future<List<String>> _fetchPagesFromMangaDex(String chapterId) async {
    try {
      final url = Uri.parse('$_mangadexBase/at-home/server/$chapterId');
      final res = await http.get(url).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final baseUrl = data['baseUrl'];
        final chapterObj = data['chapter'] ?? {};
        final hash = chapterObj['hash'];
        final List<dynamic> fileNames = chapterObj['data'] ?? [];

        if (baseUrl != null && hash != null && fileNames.isNotEmpty) {
          return fileNames.map((fn) => '$baseUrl/data/$hash/$fn').toList();
        }
      }
    } catch (_) {}
    return [];
  }
}
