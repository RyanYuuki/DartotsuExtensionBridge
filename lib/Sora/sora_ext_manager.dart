import 'dart:convert';

import 'package:dartotsu_extension_bridge/Mangayomi/http/m_client.dart';
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';

class SoraExtensionManager extends Extension {
  final http = MClient.init(reqcopyWith: {'useDartHttpClient': true});

  Stream<List<Source>> getInstalledExtensionsStream(ItemType itemType) async* {
    yield* isar.mSources
        .filter()
        .sourceIdIsNotNull()
        .and()
        .itemTypeEqualTo(itemType)
        .watch(fireImmediately: true)
        .map((sources) => sources.map((s) => _mSourceToSource(s)).toList());
  }

  Future<List<Source>> getInstalledExtensions(ItemType itemType) async {
    final sources = await isar.mSources
        .filter()
        .sourceIdIsNotNull()
        .and()
        .itemTypeEqualTo(itemType)
        .findAll();

    return sources.map((s) => _mSourceToSource(s)).toList();
  }

  Future<List<Source>> fetchAvailableExtensions(
    ItemType itemType,
    List<String>? repos,
  ) async {
    var sources = <Source>[];

    if (repos == null || repos.isEmpty) return sources;

    for (final repo in repos) {
      if (repo.trim().isEmpty) continue;

      try {
        final req = await http.get(Uri.parse(repo.trim()));
        if (req.statusCode != 200) {
          debugPrint("Failed to fetch sources from $repo: ${req.statusCode}");
          continue;
        }

        final indexData = jsonDecode(req.body) as Map<String, dynamic>;

        for (final entry in indexData.entries) {
          final extensionData = entry.value as Map<String, dynamic>;

          final type = extensionData['type']?.toString().toLowerCase();
          if (type != itemType.name.toLowerCase()) continue;

          final scriptUrl = extensionData['scriptUrl'] as String?;
          if (scriptUrl == null || scriptUrl.isEmpty) continue;

          final source = Source(
            id: _generateId(scriptUrl),
            name: extensionData['sourceName'] ?? 'Unknown',
            baseUrl: extensionData['baseUrl'] ?? '',
            lang: _convertLanguage(extensionData['language'] ?? 'all'),
            iconUrl: extensionData['iconUrl'] ?? '',
            isNsfw: false,
            version: extensionData['version'] ?? '1.0.0',
            versionLast: extensionData['version'] ?? '1.0.0',
            itemType: itemType,
            isObsolete: false,
            repo: repo,
            hasUpdate: false,
          );

          sources.add(source);
        }
      } catch (e) {
        debugPrint("Error fetching from repo $repo: $e");
        continue;
      }
    }

    return sources;
  }

  @override
  Future<void> installSource(Source source) async {
    try {
      if (source.repo == null || source.repo!.isEmpty) {
        throw Exception('No repo URL available');
      }

      final extensionInfo = await _fetchExtensionInfo(source);

      final scriptUrl = extensionInfo['scriptUrl'] as String;
      final req = await http.get(Uri.parse(scriptUrl));

      if (req.statusCode != 200) {
        throw Exception('Failed to download source code');
      }

      final mSource = MSource()
        ..sourceId = source.id
        ..name = extensionInfo['sourceName'] ?? source.name
        ..baseUrl = extensionInfo['baseUrl'] ?? source.baseUrl
        ..apiUrl =
            extensionInfo['searchBaseUrl'] ?? extensionInfo['baseUrl'] ?? ''
        ..lang = source.lang
        ..iconUrl = extensionInfo['iconUrl'] ?? source.iconUrl
        ..version = extensionInfo['version'] ?? source.version
        ..versionLast = extensionInfo['version'] ?? source.version
        ..itemType = ItemType.anime
        ..sourceCode = req.body
        ..typeSource = extensionInfo['streamType'] ?? 'HLS'
        ..headers = jsonEncode({
          'scriptUrl': scriptUrl,
          'quality': extensionInfo['quality'] ?? '1080p',
          'asyncJS': extensionInfo['asyncJS'] ?? true,
          'softsub': extensionInfo['softsub'] ?? false,
          'downloadSupport': extensionInfo['downloadSupport'] ?? false,
        })
        ..repo = source.repo
        ..isActive = true
        ..isAdded = true
        ..isFullData = true
        ..isNsfw = false
        ..isPinned = false
        ..lastUsed = false
        ..isObsolete = false
        ..isLocal = false
        ..dateFormat = ''
        ..dateFormatLocale = ''
        ..hasCloudflare = false
        ..appMinVerReq = '';

      await isar.writeTxn(() async {
        await isar.mSources.put(mSource);
      });
    } catch (e) {
      debugPrint("Error installing source: $e");
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    try {
      final mSource = await isar.mSources
          .filter()
          .sourceIdEqualTo(source.id)
          .findFirst();

      if (mSource == null) {
        throw Exception('Source not found');
      }

      await isar.writeTxn(() async {
        await isar.mSources.delete(mSource.id!);
      });
    } catch (e) {
      debugPrint("Error uninstalling source: $e");
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    try {
      if (source.repo == null || source.repo!.isEmpty) {
        throw Exception('No repo URL available');
      }

      final extensionInfo = await _fetchExtensionInfo(source);

      final scriptUrl = extensionInfo['scriptUrl'] as String;
      final req = await http.get(Uri.parse(scriptUrl));

      if (req.statusCode != 200) {
        throw Exception('Failed to download source code');
      }

      final existingSource = await isar.mSources
          .filter()
          .sourceIdEqualTo(source.id)
          .findFirst();

      if (existingSource == null) {
        throw Exception('Source not found');
      }

      existingSource
        ..version = extensionInfo['version'] ?? source.version
        ..versionLast = extensionInfo['version'] ?? source.version
        ..sourceCode = req.body
        ..baseUrl = extensionInfo['baseUrl'] ?? existingSource.baseUrl
        ..apiUrl =
            extensionInfo['searchBaseUrl'] ??
            extensionInfo['baseUrl'] ??
            existingSource.apiUrl
        ..typeSource = extensionInfo['streamType'] ?? existingSource.typeSource
        ..headers = jsonEncode({
          'scriptUrl': scriptUrl,
          'quality': extensionInfo['quality'] ?? '1080p',
          'asyncJS': extensionInfo['asyncJS'] ?? true,
          'softsub': extensionInfo['softsub'] ?? false,
          'downloadSupport': extensionInfo['downloadSupport'] ?? false,
        });

      await isar.writeTxn(() async {
        await isar.mSources.put(existingSource);
      });
    } catch (e) {
      debugPrint("Error updating source: $e");
      rethrow;
    }
  }

  Future<MSource> getSource(String sourceId) async {
    final mSource = await isar.mSources
        .filter()
        .sourceIdEqualTo(sourceId)
        .findFirst();

    if (mSource == null) {
      throw Exception('Source not found');
    }

    return mSource;
  }

  Future<Map<String, dynamic>> _fetchExtensionInfo(Source source) async {
    final req = await http.get(Uri.parse(source.repo!));
    if (req.statusCode != 200) {
      throw Exception('Failed to fetch repo index');
    }

    final indexData = jsonDecode(req.body) as Map<String, dynamic>;

    for (final entry in indexData.entries) {
      final extensionData = entry.value as Map<String, dynamic>;
      final extensionId = _generateId(extensionData['scriptUrl'] ?? entry.key);

      if (extensionId == source.id) {
        return extensionData;
      }
    }

    throw Exception('Source not found in repo');
  }

  String _generateId(String scriptUrl) {
    return scriptUrl.hashCode.abs().toString();
  }

  String _convertLanguage(String language) {
    final langLower = language.toLowerCase();

    if (langLower.contains('english')) return 'en';
    if (langLower.contains('japanese') || langLower.contains('日本語')) {
      return 'ja';
    }
    if (langLower.contains('chinese') || langLower.contains('中文')) return 'zh';
    if (langLower.contains('spanish') || langLower.contains('español')) {
      return 'es';
    }
    if (langLower.contains('french') || langLower.contains('français')) {
      return 'fr';
    }
    if (langLower.contains('german') || langLower.contains('deutsch')) {
      return 'de';
    }
    if (langLower.contains('portuguese') || langLower.contains('português')) {
      return 'pt';
    }
    if (langLower.contains('russian') || langLower.contains('русский')) {
      return 'ru';
    }
    if (langLower.contains('korean') || langLower.contains('한국어')) return 'ko';
    if (langLower.contains('italian') || langLower.contains('italiano')) {
      return 'it';
    }
    if (langLower.contains('arabic') || langLower.contains('العربية')) {
      return 'ar';
    }
    if (langLower.contains('thai') || langLower.contains('ไทย')) return 'th';
    if (langLower.contains('vietnamese') || langLower.contains('tiếng việt')) {
      return 'vi';
    }
    if (langLower.contains('indonesian') ||
        langLower.contains('bahasa indonesia')) {
      return 'id';
    }
    if (langLower.contains('turkish') || langLower.contains('türkçe')) {
      return 'tr';
    }
    if (langLower.contains('polish') || langLower.contains('polski')) {
      return 'pl';
    }
    if (langLower.contains('ukrainian') || langLower.contains('українська')) {
      return 'uk';
    }

    return 'all';
  }

  Source _mSourceToSource(MSource mSource) {
    return Source(
      id: mSource.sourceId,
      name: mSource.name,
      baseUrl: mSource.baseUrl,
      lang: mSource.lang,
      iconUrl: mSource.iconUrl,
      isNsfw: mSource.isNsfw,
      version: mSource.version,
      versionLast: mSource.versionLast,
      itemType: mSource.itemType,
      isObsolete: mSource.isObsolete,
      repo: mSource.repo,
      hasUpdate: false,
    );
  }

  @override
  Future<void> initialize() {
    throw UnimplementedError();
  }
}
