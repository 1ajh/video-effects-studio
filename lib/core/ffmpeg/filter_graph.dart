/// Small helper for assembling an FFmpeg `-filter_complex` graph with
/// automatically generated, collision-free pad labels.
class FilterGraph {
  FilterGraph({String prefix = 'n'}) : _prefix = prefix;

  final String _prefix;
  final List<String> _chains = [];
  int _counter = 0;

  /// Returns a fresh, unused pad label (without brackets).
  String label([String hint = '']) => '$_prefix${hint.isEmpty ? '' : '_$hint'}${_counter++}';

  /// Appends `[input]filters[out]` and returns `out`.
  ///
  /// [filters] is a comma separated filter chain. An empty chain is replaced
  /// with the matching null filter so the graph stays valid.
  String chain(String input, String filters, {bool audio = false, String? out}) {
    final o = out ?? label();
    final body = filters.trim().isEmpty ? (audio ? 'anull' : 'null') : filters;
    _chains.add('[$input]$body[$o]');
    return o;
  }

  /// Video chain helper.
  String v(String input, String filters) => chain(input, filters);

  /// Audio chain helper.
  String a(String input, String filters) => chain(input, filters, audio: true);

  /// Splits a stream into [count] copies.
  List<String> split(String input, int count, {bool audio = false}) {
    if (count < 1) throw ArgumentError.value(count, 'count');
    final outs = List.generate(count, (_) => label());
    if (count == 1) {
      _chains.add('[$input]${audio ? 'anull' : 'null'}[${outs.first}]');
    } else {
      _chains.add('[$input]${audio ? 'asplit' : 'split'}=$count${outs.map((o) => '[$o]').join()}');
    }
    return outs;
  }

  /// Feeds several inputs into one multi-input filter (hstack, amix, ...).
  String join(List<String> inputs, String filter, {String? out}) {
    final o = out ?? label();
    _chains.add('${inputs.map((i) => '[$i]').join()}$filter[$o]');
    return o;
  }

  /// Adds a source filter (no inputs), e.g. `aevalsrc=...`.
  String source(String filter) {
    final o = label();
    _chains.add('$filter[$o]');
    return o;
  }

  bool get isEmpty => _chains.isEmpty;

  /// The complete graph, suitable for `-filter_complex`.
  String build() => _chains.join(';');

  @override
  String toString() => build();
}
