import 'package:flutter/foundation.dart';

import '../core/effects/custom_effect.dart';
import '../core/effects/effect.dart';
import '../core/effects/registry.dart';
import 'store.dart';

/// A named set of parameter values for one effect.
class Preset {
  const Preset(this.name, this.values);
  final String name;
  final Map<String, Object?> values;

  Map<String, Object?> toJson() => {'name': name, 'values': values};

  factory Preset.fromJson(Map<String, Object?> json) =>
      Preset(json['name'] as String? ?? 'Preset', (json['values'] as Map?)?.cast<String, Object?>() ?? const {});
}

/// Favorites, recents, presets and custom effects — the user's library.
class LibraryController extends ChangeNotifier {
  LibraryController(this._store) {
    _favorites = {...?_store.readJson<List>('favorites')?.cast<String>()};
    _recents = [...?_store.readJson<List>('recents')?.cast<String>()];
    final presets = _store.readJson<Map<String, Object?>>('presets') ?? const {};
    _presets = {
      for (final e in presets.entries)
        e.key: [for (final p in (e.value as List? ?? const []).cast<Map>()) Preset.fromJson(p.cast<String, Object?>())],
    };
    _custom = [
      for (final c in (_store.readJson<List>('customEffects') ?? const []).cast<Map>())
        CustomEffectDef.fromJson(c.cast<String, Object?>()),
    ];
    _registry = EffectRegistry(custom: _custom);
  }

  final Store _store;
  late Set<String> _favorites;
  late List<String> _recents;
  late Map<String, List<Preset>> _presets;
  late List<CustomEffectDef> _custom;
  late EffectRegistry _registry;

  EffectRegistry get registry => _registry;
  Set<String> get favorites => Set.unmodifiable(_favorites);
  List<String> get recents => List.unmodifiable(_recents);
  List<CustomEffectDef> get customEffects => List.unmodifiable(_custom);

  bool isFavorite(String id) => _favorites.contains(id);

  void toggleFavorite(String id) {
    if (!_favorites.remove(id)) _favorites.add(id);
    _store.writeJson('favorites', _favorites.toList());
    notifyListeners();
  }

  void markUsed(String id) {
    _recents.remove(id);
    _recents.insert(0, id);
    if (_recents.length > 24) _recents = _recents.sublist(0, 24);
    _store.writeJson('recents', _recents);
    notifyListeners();
  }

  List<Effect> resolve(Iterable<String> ids) => ids.map(_registry.byId).whereType<Effect>().toList();

  // --- presets ---------------------------------------------------------------

  List<Preset> presetsFor(String effectId) => List.unmodifiable(_presets[effectId] ?? const []);

  void savePreset(String effectId, String name, Map<String, Object?> values) {
    final list = [...?_presets[effectId]]..removeWhere((p) => p.name == name);
    list.add(Preset(name, Map.of(values)));
    _presets[effectId] = list;
    _persistPresets();
  }

  void deletePreset(String effectId, String name) {
    _presets[effectId]?.removeWhere((p) => p.name == name);
    _persistPresets();
  }

  void _persistPresets() {
    _store.writeJson('presets', {
      for (final e in _presets.entries) e.key: [for (final p in e.value) p.toJson()],
    });
    notifyListeners();
  }

  // --- custom effects --------------------------------------------------------

  CustomEffectDef? customById(String id) {
    for (final c in _custom) {
      if (c.id == id) return c;
    }
    return null;
  }

  void saveCustom(CustomEffectDef def) {
    final i = _custom.indexWhere((c) => c.id == def.id);
    if (i >= 0) {
      _custom[i] = def;
    } else {
      _custom.add(def);
    }
    _persistCustom();
  }

  void deleteCustom(String id) {
    _custom.removeWhere((c) => c.id == id);
    _favorites.remove(id);
    _recents.remove(id);
    _persistCustom();
  }

  void _persistCustom() {
    _registry = EffectRegistry(custom: _custom);
    _store.writeJson('customEffects', [for (final c in _custom) c.toJson()]);
    notifyListeners();
  }

  Future<void> clear() async {
    _favorites.clear();
    _recents.clear();
    _presets.clear();
    await _store.writeJson('favorites', <String>[]);
    await _store.writeJson('recents', <String>[]);
    await _store.writeJson('presets', <String, Object?>{});
    notifyListeners();
  }
}
