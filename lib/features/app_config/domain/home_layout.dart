/// Sections the home screen knows how to render.
enum HomeSection { banner, categories, deals, allProducts }

/// Server-driven home screen layout.
///
/// ## TODO(F2) - implement [HomeLayout.parse]
///
/// Contract (checked by hidden tests):
/// * Input is the raw `home_sections` remote config value: a JSON array of
///   strings. Known ids: `banner`, `categories`, `deals`, `all_products`.
/// * Output keeps the order given by the config.
/// * Unknown ids are ignored (older app versions must not break when the
///   backend adds a new section type).
/// * Duplicates are ignored (first occurrence wins).
/// * null, malformed JSON, a non-array value, or a result with zero known
///   sections -> [HomeLayout.defaultSections].
class HomeLayout {
  const HomeLayout._();

  static const List<HomeSection> defaultSections = [
    HomeSection.categories,
    HomeSection.allProducts,
  ];

  static List<HomeSection> parse(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return defaultSections;
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return defaultSections;

      final result = <HomeSection>[];
      final seen = <HomeSection>{};

      for (final item in decoded) {
        if (item is! String) continue;
        final section = _fromId(item.trim());
        if (section != null && seen.add(section)) {
          result.add(section);
        }
      }

      if (result.isEmpty) return defaultSections;
      return result;
    } catch (_) {
      return defaultSections;
    }
  }

  static HomeSection? _fromId(String id) {
    switch (id) {
      case 'banner':
        return HomeSection.banner;
      case 'categories':
        return HomeSection.categories;
      case 'deals':
        return HomeSection.deals;
      case 'all_products':
        return HomeSection.allProducts;
      default:
        return null;
    }
  }
}
