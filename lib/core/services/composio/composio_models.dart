class ComposioToolkit {
  final String slug;
  final String name;
  final String? logo;
  final String? description;
  final String category;
  final int toolCount;
  final bool isConnected;

  const ComposioToolkit({
    required this.slug,
    required this.name,
    this.logo,
    this.description,
    this.category = 'General',
    this.toolCount = 0,
    this.isConnected = false,
  });

  String get logoUrl {
    final l = logo?.trim();
    if (l != null && l.isNotEmpty && !l.contains('assets.composio.dev')) {
      return l;
    }
    return 'https://logos.composio.dev/api/${slug.toLowerCase()}';
  }

  ComposioToolkit copyWith({
    String? slug,
    String? name,
    String? logo,
    String? description,
    String? category,
    int? toolCount,
    bool? isConnected,
  }) {
    return ComposioToolkit(
      slug: slug ?? this.slug,
      name: name ?? this.name,
      logo: logo ?? this.logo,
      description: description ?? this.description,
      category: category ?? this.category,
      toolCount: toolCount ?? this.toolCount,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  factory ComposioToolkit.fromJson(
    Map<String, dynamic> json, {
    bool isConnected = false,
  }) {
    final slug = (json['slug'] ?? json['key'] ?? json['id'] ?? '').toString();
    final name = (json['name'] ?? json['displayName'] ?? json['title'] ?? slug)
        .toString();
    final rawLogo = json['logo'] as String? ?? json['icon'] as String?;
    final logo =
        (rawLogo != null &&
            rawLogo.isNotEmpty &&
            !rawLogo.contains('assets.composio.dev'))
        ? rawLogo
        : 'https://logos.composio.dev/api/${slug.toLowerCase()}';
    final description =
        json['description'] as String? ?? json['summary'] as String?;
    final category =
        (json['category'] ??
                (json['categories'] is List &&
                        (json['categories'] as List).isNotEmpty
                    ? (json['categories'] as List).first
                    : null) ??
                'General')
            .toString();
    final toolCount =
        (json['toolCount'] ??
                json['actionsCount'] ??
                (json['tools'] is List ? (json['tools'] as List).length : 0))
            as int? ??
        0;

    return ComposioToolkit(
      slug: slug,
      name: name,
      logo: logo,
      description: description,
      category: category,
      toolCount: toolCount,
      isConnected: isConnected,
    );
  }

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'name': name,
    'logo': logo,
    'description': description,
    'category': category,
    'toolCount': toolCount,
    'isConnected': isConnected,
  };
}
