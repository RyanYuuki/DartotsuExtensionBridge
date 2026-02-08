import 'package:dartotsu_extension_bridge/Sora/sora_ext_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fetches sora sources', () async {
    final manager = SoraExtensionManager();

    final sources = await manager.fetchAvailableAnimeExtensions([
      "https://git.luna-app.eu/50n50/sources/raw/branch/main/index.json",
    ]);

    expect(sources, isNotEmpty);
    expect(sources.first.name, isNotNull);
  });
}
