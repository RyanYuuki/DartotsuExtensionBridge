import 'dart:convert';

import 'package:dartotsu_extension_bridge/Mangayomi/Eval/dart/model/video.dart';
import 'package:dartotsu_extension_bridge/Mangayomi/interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart';

import '../Mangayomi/Eval/dart/model/filter.dart';
import '../Mangayomi/Eval/dart/model/m_chapter.dart';
import '../Mangayomi/Eval/dart/model/m_manga.dart';
import '../Mangayomi/Eval/dart/model/m_pages.dart';
import '../Mangayomi/Eval/dart/model/page.dart';
import '../Mangayomi/Eval/dart/model/source_preference.dart';
import '../Mangayomi/Models/Source.dart';

class SoraExtensionService implements ExtensionService {
  @override
  late MSource source;

  late JavascriptRuntime _jsRuntime;
  bool _isInitialized = false;

  SoraExtensionService(this.source) {
    _jsRuntime = getJavascriptRuntime();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      _initializeFetchPolyfill();

      if (source.sourceCode != null && source.sourceCode!.isNotEmpty) {
        final result = _jsRuntime.evaluate(source.sourceCode!);
        if (result.isError) {
          throw Exception('Failed to load source code: ${result.stringResult}');
        }
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint("Error initializing SoraExtensionService: $e");
      rethrow;
    }
  }

  void _initializeFetchPolyfill() {
    const fetchPolyfill = '''
      globalThis.fetchv2 = async function(url, options = {}) {
        return {
          text: async () => __dartFetch(url, JSON.stringify(options)),
          json: async () => JSON.parse(__dartFetch(url, JSON.stringify(options))),
          statusCode: 200
        };
      };
    ''';

    _jsRuntime.evaluate(fetchPolyfill);
  }

  @override
  String get sourceBaseUrl => source.baseUrl ?? '';

  @override
  bool get supportsLatest => false;

  @override
  Map<String, String> getHeaders() {
    try {
      if (source.headers != null && source.headers!.isNotEmpty) {
        final headers = jsonDecode(source.headers!);
        if (headers is Map) {
          return Map<String, String>.from(headers);
        }
      }
    } catch (e) {
      debugPrint('Error parsing headers: $e');
    }
    return {};
  }

  @override
  Future<MPages> getPopular(int page) async {
    return MPages(list: []);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return MPages(list: []);
  }

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) async {
    if (!_isInitialized) await _initialize();

    try {
      final jsCode =
          '''
        (async () => {
          const results = await searchResults("${_escapeJs(query)}");
          return results;
        })();
      ''';

      final result = await _jsRuntime.evaluateAsync(jsCode);
      final jsonResult = result.stringResult;

      if (jsonResult.isEmpty || jsonResult == 'undefined') {
        return MPages(list: []);
      }

      final List<dynamic> searchResults = jsonDecode(jsonResult);
      final mangaList = searchResults.map((item) {
        return MManga(
          name: item['title'] ?? '',
          link: item['href'] ?? '',
          imageUrl: item['image'] ?? '',
        );
      }).toList();

      return MPages(list: mangaList, hasNextPage: false);
    } catch (e) {
      debugPrint("Error in search: $e");
      return MPages(list: []);
    }
  }

  @override
  Future<MManga> getDetail(String url) async {
    if (!_isInitialized) await _initialize();

    try {
      final detailsCode =
          '''
        (async () => {
          const details = await extractDetails("${_escapeJs(url)}");
          return details;
        })();
      ''';

      final detailsResult = await _jsRuntime.evaluateAsync(detailsCode);
      final detailsJson = jsonDecode(detailsResult.stringResult);
      final details = detailsJson[0];

      final episodesCode =
          '''
        (async () => {
          const episodes = await extractEpisodes("${_escapeJs(url)}");
          return episodes;
        })();
      ''';

      final episodesResult = await _jsRuntime.evaluateAsync(episodesCode);
      final episodesJson = jsonDecode(episodesResult.stringResult);

      final episodeList = (episodesJson as List).map((ep) {
        return MChapter(
          name: 'Episode ${ep['number']}',
          url: ep['href'] ?? '',
          dateUpload: '',
          scanlator: '',
        );
      }).toList();

      return MManga(
        name: '',
        link: url,
        imageUrl: '',
        description: details['description'] ?? 'N/A',
        genre: [],
        status: Status.unknown,
        author: '',
        artist: '',
        chapters: episodeList,
      );
    } catch (e) {
      debugPrint("Error getting detail: $e");
      return MManga(name: '', link: url, imageUrl: '');
    }
  }

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    return [];
  }

  @override
  Future<List<Video>> getVideoList(String url) async {
    if (!_isInitialized) await _initialize();

    try {
      final jsCode =
          '''
        (async () => {
          const stream = await extractStreamUrl("${_escapeJs(url)}");
          return JSON.stringify(stream);
        })();
      ''';

      final result = await _jsRuntime.evaluateAsync(jsCode);
      final jsonResult = result.stringResult;

      if (jsonResult.isEmpty ||
          jsonResult == 'undefined' ||
          jsonResult == '"https://error.org/"') {
        return [];
      }

      dynamic streamData;
      try {
        streamData = jsonDecode(jsonResult);
      } catch (e) {
        streamData = jsonDecode(jsonDecode(jsonResult));
      }

      final List<Video> videos = [];

      if (streamData is List) {
        for (final stream in streamData) {
          videos.add(_parseVideoStream(stream));
        }
      } else if (streamData is Map) {
        videos.add(_parseVideoStream(streamData));
      }

      return videos;
    } catch (e) {
      debugPrint("Error getting video list: $e");
      return [];
    }
  }

  Video _parseVideoStream(Map<dynamic, dynamic> stream) {
    final subtitles = <Track>[];
    final audios = <Track>[];

    if (stream['subtitles'] != null && stream['subtitles'] is List) {
      for (final sub in stream['subtitles']) {
        subtitles.add(
          Track(
            file: sub['file'] ?? sub['url'],
            label: sub['label'] ?? sub['lang'] ?? 'Unknown',
          ),
        );
      }
    }

    if (stream['audios'] != null && stream['audios'] is List) {
      for (final audio in stream['audios']) {
        audios.add(
          Track(
            file: audio['file'] ?? audio['url'],
            label: audio['label'] ?? audio['lang'] ?? 'Unknown',
          ),
        );
      }
    }

    return Video(
      stream['title'] ?? stream['quality'] ?? 'Default',
      stream['url'] ?? stream['file'] ?? '',
      stream['quality'] ?? 'auto',
      headers: stream['headers'] != null
          ? Map<String, String>.from(stream['headers'])
          : null,
      subtitles: subtitles.isEmpty ? null : subtitles,
      audios: audios.isEmpty ? null : audios,
    );
  }

  @override
  Future<String> getHtmlContent(String name, String url) async {
    return '';
  }

  @override
  Future<String> cleanHtmlContent(String html) async {
    return html;
  }

  @override
  FilterList getFilterList() {
    return FilterList([]);
  }

  @override
  List<SourcePreference> getSourcePreferences() {
    return [];
  }

  String _escapeJs(String str) {
    return str
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  void dispose() {
    _isInitialized = false;
  }
}
