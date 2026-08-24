class StationNameMatcher {
  StationNameMatcher._();

  static final StationNameMatcher instance = StationNameMatcher._();

  static const Map<String, String> _aliasTable = {
    'kentonmen': 'kentomen',
    'kinrara bk 5': 'kinrara',
  };

  String normalize(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    s = s.replaceFirst(RegExp(r'^bank rakyat\s+'), '');
    s = s.replaceFirst(RegExp(r'^cgc\s+'), '');
    s = s.replaceAll(
        RegExp(r'\s*-\s*(?:redone|uob|cbp coopbank pertama|the face style|maybank)\s*$'),
        '',
      )
      .trim();
    s = s.replaceAll(RegExp(r'\s*-\s*'), ' ');
    s = s.replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}');
    s = s.replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  bool match(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na == nb) return true;
    return _aliasTable[na] == nb || _aliasTable[nb] == na;
  }

  String displayName(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    s = s.replaceFirst(RegExp(r'^bank rakyat\s+', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'^cgc\s+', caseSensitive: false), '');
    s = s
        .replaceAll(
          RegExp(
            r'\s*-\s*(?:redone|uob|cbp coopbank pertama|the face style|maybank)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }
}
