import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/effects/effect.dart';
import '../core/effects/registry.dart';
import '../core/render/render_engine.dart';

/// One effect in the compilation, with its own parameter values.
class CompItem {
  CompItem(this.effectId, Map<String, Object?> params)
    : uid = '${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
      params = Map.of(params);

  static int _seq = 0;
  final String uid;
  final String effectId;
  Map<String, Object?> params;
}

/// The ordered list of effects rendered one after another.
class CompilationController extends ChangeNotifier {
  CompilationController({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final List<CompItem> _items = [];
  int? _selected;

  List<CompItem> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  int? get selectedIndex => _selected;
  CompItem? get selectedItem => _selected == null ? null : _items[_selected!];

  void add(Effect e, Map<String, Object?> params) {
    _items.add(CompItem(e.id, params));
    notifyListeners();
  }

  /// Appends effects with their default parameters.
  void addAll(Iterable<Effect> effects) {
    _items.addAll(effects.map((e) => CompItem(e.id, e.defaults())));
    notifyListeners();
  }

  /// Replaces the list with every effect in the library.
  void selectAll(EffectRegistry registry) {
    _items
      ..clear()
      ..addAll(registry.all.map((e) => CompItem(e.id, e.defaults())));
    _selected = null;
    notifyListeners();
  }

  void addCategory(EffectRegistry registry, EffectCategory c) => addAll(registry.inCategory(c));

  /// Replaces the list with [count] random effects (optionally from one
  /// category), without repeats.
  void randomize(EffectRegistry registry, int count, {EffectCategory? category}) {
    final pool = [...(category == null ? registry.all : registry.inCategory(category))]..shuffle(_random);
    _items
      ..clear()
      ..addAll(pool.take(count).map((e) => CompItem(e.id, e.defaults())));
    _selected = null;
    notifyListeners();
  }

  void shuffle() {
    final sel = selectedItem;
    _items.shuffle(_random);
    _selected = sel == null ? null : _items.indexOf(sel);
    notifyListeners();
  }

  /// Moves an item; [newIndex] is its final position in the list.
  void move(int oldIndex, int newIndex) {
    final sel = selectedItem;
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);
    _selected = sel == null ? null : _items.indexOf(sel);
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    final sel = selectedItem;
    _items.removeAt(index);
    _selected = sel == null ? null : _items.indexOf(sel);
    if (_selected == -1) _selected = null;
    notifyListeners();
  }

  /// Drops items whose effect no longer exists (deleted custom effects).
  void prune(EffectRegistry registry) {
    final before = _items.length;
    _items.removeWhere((i) => registry.byId(i.effectId) == null);
    if (_items.length != before) {
      _selected = null;
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    _selected = null;
    notifyListeners();
  }

  void select(int? index) {
    _selected = index;
    notifyListeners();
  }

  void setItemParam(int index, String id, Object? value) {
    _items[index].params = {..._items[index].params, id: value};
    notifyListeners();
  }

  void setItemParams(int index, Map<String, Object?> values) {
    _items[index].params = Map.of(values);
    notifyListeners();
  }

  List<CompilationEntry> entries(EffectRegistry registry) => [
    for (final i in _items)
      if (registry.byId(i.effectId) case final e?) CompilationEntry(e, i.params),
  ];

  /// Estimated output length in seconds.
  double estimateSeconds(
    EffectRegistry registry,
    double inputSeconds, {
    required bool originalFirst,
    required LabelMode labelMode,
    double titleCardSeconds = 1.2,
  }) {
    var total = originalFirst ? inputSeconds : 0.0;
    for (final e in entries(registry)) {
      total += e.effect.outputSecondsFor(e.params, inputSeconds);
    }
    if (labelMode == LabelMode.titleCard) {
      total += titleCardSeconds * (_items.length + (originalFirst ? 1 : 0));
    }
    return total;
  }
}
