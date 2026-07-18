/// Mirrors the backend's offset/limit pagination envelope.
class Page<T> {
  Page({required this.items, required this.total, required this.offset, required this.limit});

  final List<T> items;
  final int total;
  final int offset;
  final int limit;

  factory Page.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItem,
  ) {
    return Page(
      items: (json['items'] as List<dynamic>)
          .map((e) => fromItem(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      offset: json['offset'] as int,
      limit: json['limit'] as int,
    );
  }
}
