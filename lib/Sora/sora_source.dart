import 'package:dartotsu_extension_bridge/ExtensionManager.dart';
import 'package:isar_community/isar.dart';

import '../Models/Source.dart';

part 'sora_source.g.dart';

@collection
class SoraSource {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String? sourceId;

  String? name;
  String? baseUrl;
  String? searchBaseUrl;
  String? lang;
  String? iconUrl;
  String? version;
  int? itemType;
  String? sourceCode;
  String? scriptUrl;
  String? streamType;
  String? quality;
  bool? asyncJS;
  bool? softsub;
  bool? downloadSupport;
  String? repo;
  bool? isNsfw;
  bool? isObsolete;
  DateTime? dateAdded;

  SoraSource();

  Source toSource() {
    return Source(
      id: sourceId,
      name: name,
      baseUrl: baseUrl,
      lang: lang,
      iconUrl: iconUrl,
      version: version,
      versionLast: version,
      itemType: ItemType.values[itemType ?? 0],
      isObsolete: isObsolete ?? false,
      repo: repo,
      hasUpdate: false,
      extensionType: ExtensionType.sora,
      isNsfw: isNsfw ?? false,
    );
  }
}
