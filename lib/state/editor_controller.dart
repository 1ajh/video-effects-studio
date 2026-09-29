import 'package:flutter/foundation.dart';

import '../core/effects/effect.dart';
import 'library_controller.dart';

enum EditorMode { single, compilation, sparta }

/// Browser filter: everything, favorites, recents, or a category.
@immutable
class BrowserFilter {
  const BrowserFilter._(this.kind, [this.category]);
  static const all = BrowserFilter._('all');
  static const favorites = BrowserFilter._('fav');
  static const recent = BrowserFilter._('recent');
  const BrowserFilter.category(EffectCategory c) : this._('cat', c);

  final String kind;
  final EffectCategory? category;

  @override
  bool operator ==(Object other) => other is BrowserFilter && other.kind == kind && other.category == category;

  @override
  int get hashCode => Object.hash(kind, category);
}

/// Which effect is selected, its parameter values, and browser filters.
class EditorController extends ChangeNotifier {
  EditorController(this._library) {
    _library.addListener(_onLibrary);
  }

  final LibraryController _library;

  EditorMode _mode = EditorMode.single;
  String? _selectedId;
  final Map<String, Map<String, Object?>> _params = {};
  BrowserFilter _filter = BrowserFilter.all;
  String _search = '';

  EditorMode get mode => _mode;
  BrowserFilter get filter => _filter;
  String get search => _search;

  Effect? get selected => _selectedId == null ? null : _library.registry.byId(_selectedId!);

  void _onLibrary() {
    // A deleted custom effect may have been selected.
    if (_selectedId != null && _library.registry.byId(_selectedId!) == null) _selectedId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _library.removeListener(_onLibrary);
    super.dispose();
  }

  void setMode(EditorMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  void select(Effect e) {
    if (_selectedId == e.id) return;
    _selectedId = e.id;
    notifyListeners();
  }

  void clearSelection() {
    _selectedId = null;
    notifyListeners();
  }

  /// Current parameter values for [e] (remembered per effect).
  Map<String, Object?> paramsFor(Effect e) => {...e.defaults(), ...?_params[e.id]};

  void setParam(Effect e, String id, Object? value) {
    (_params[e.id] ??= {})[id] = value;
    notifyListeners();
  }

  void setParams(Effect e, Map<String, Object?> values) {
    _params[e.id] = Map.of(values);
    notifyListeners();
  }

  void resetParams(Effect e) {
    _params.remove(e.id);
    notifyListeners();
  }

  void setFilter(BrowserFilter f) {
    _filter = f;
    notifyListeners();
  }

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  /// Effects visible in the browser for the current filter + search.
  List<Effect> visibleEffects() {
    final reg = _library.registry;
    List<Effect> base;
    switch (_filter.kind) {
      case 'fav':
        base = reg.all.where((e) => _library.isFavorite(e.id)).toList();
      case 'recent':
        base = _library.resolve(_library.recents);
      case 'cat':
        base = reg.inCategory(_filter.category!);
      default:
        base = reg.all;
    }
    if (_search.trim().isEmpty) return base;
    // Search always spans the whole library so nothing is "hidden".
    final source = _filter.kind == 'all' ? base : reg.all;
    return source.where((e) => e.matches(_search)).toList();
  }
}
