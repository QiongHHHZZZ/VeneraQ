const searchLanguageFilterSourceKeys = {'nhentai', 'ehentai'};

String applySearchLanguageFilter(
  String text, {
  required String sourceKey,
  required String setting,
}) {
  if (setting == 'none') {
    return text;
  }
  if (!searchLanguageFilterSourceKeys.contains(sourceKey)) {
    return text;
  }
  if (text.contains('language:')) {
    return text;
  }
  return '$text language:$setting';
}
