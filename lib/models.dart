import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Chuẩn hóa mã để so khớp: viết hoa, bỏ khoảng trắng / dấu gạch / ký tự lạ.
String normCode(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Gom ĐVT: "Cái", "CÁI" => "CÁI"
String unitKey(String u) {
  final k = u.trim().toUpperCase();
  return k.isEmpty ? '(trống)' : k;
}

/// GIÁ BÌNH QUÂN = Giá trị tồn / Số lượng tồn.
/// Nếu tồn = 0 thì dùng [fallback] (ví dụ cột "Giá BQ" trong file nếu có).
double calcAvgPrice(double qty, double value, [double fallback = 0]) =>
    qty > 0 ? value / qty : fallback;

enum ItemStatus { match, short, over, notCounted, noStock }

class Item {
  Item({
    required this.code,
    required this.name,
    required this.unit,
    required this.sysQty,
    required this.sysValue,
    this.listPrice = 0,
    this.counted = 0,
    this.touched = false,
    this.lastScan,
  });

  final String code;
  final String name;
  final String unit;
  double sysQty; // tồn lý thuyết
  double sysValue; // giá trị tồn lý thuyết
  double listPrice; // cột Giá BQ trong file (nếu có)
  double counted; // số lượng đã kiểm
  bool touched; // đã quét / nhập tay ít nhất 1 lần
  DateTime? lastScan;

  late final String key = normCode(code);

  double get avgPrice => calcAvgPrice(sysQty, sysValue, listPrice);
  double get diff {
    final d = counted - sysQty;
    return d.abs() < 1e-6 ? 0 : d;
  }

  double get countedValue => counted * avgPrice;
  double get diffValue => diff * avgPrice;

  ItemStatus get status {
    if (!touched) return sysQty > 0 ? ItemStatus.notCounted : ItemStatus.noStock;
    if (diff == 0) return ItemStatus.match;
    return diff < 0 ? ItemStatus.short : ItemStatus.over;
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'unit': unit,
        'sysQty': sysQty,
        'sysValue': sysValue,
        'listPrice': listPrice,
        'counted': counted,
        'touched': touched,
        'lastScan': lastScan?.toIso8601String(),
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        code: j['code'],
        name: j['name'],
        unit: j['unit'],
        sysQty: (j['sysQty'] as num).toDouble(),
        sysValue: (j['sysValue'] as num).toDouble(),
        listPrice: (j['listPrice'] as num? ?? 0).toDouble(),
        counted: (j['counted'] as num).toDouble(),
        touched: j['touched'] as bool,
        lastScan: j['lastScan'] == null ? null : DateTime.tryParse(j['lastScan']),
      );
}

class ScanResult {
  ScanResult(this.code, this.item, this.qty);
  final String code; // mã đọc được
  final Item? item; // null = ngoài danh sách
  final double qty;
}

class _Event {
  _Event(this.code, this.item, this.qty);
  final String code;
  final Item? item;
  final double qty;
}

class Inventory extends ChangeNotifier {
  List<Item> items = [];
  final Map<String, Item> _index = {};
  final Map<String, double> extras = {}; // mã ngoài danh sách -> SL đếm được
  String sourceName = '';
  DateTime? importedAt;
  final List<_Event> _log = [];

  bool get hasData => items.isNotEmpty;
  bool get hasAnyCount => items.any((i) => i.touched) || extras.isNotEmpty;
  bool get canUndo => _log.isNotEmpty;

  // ---------- lưu / tải ----------
  Future<File> _file() async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/inventory_state.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      items = (j['items'] as List).map((e) => Item.fromJson(e as Map<String, dynamic>)).toList();
      extras
        ..clear()
        ..addAll((j['extras'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      sourceName = j['sourceName'] ?? '';
      importedAt = j['importedAt'] == null ? null : DateTime.tryParse(j['importedAt']);
      _reindex();
    } catch (_) {
      // file hỏng -> bỏ qua
    }
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'items': items.map((e) => e.toJson()).toList(),
        'extras': extras,
        'sourceName': sourceName,
        'importedAt': importedAt?.toIso8601String(),
      }));
    } catch (_) {}
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  void _reindex() {
    _index
      ..clear()
      ..addEntries(items.map((e) => MapEntry(e.key, e)));
  }

  // ---------- thao tác ----------
  void setItems(List<Item> list, String name) {
    items = list;
    extras.clear();
    _log.clear();
    sourceName = name;
    importedAt = DateTime.now();
    _reindex();
    _changed();
  }

  void resetCounts() {
    for (final i in items) {
      i.counted = 0;
      i.touched = false;
      i.lastScan = null;
    }
    extras.clear();
    _log.clear();
    _changed();
  }

  /// Tìm hàng theo mã quét được. Khớp chính xác trước, sau đó khớp "chứa".
  Item? find(String raw) {
    final b = normCode(raw);
    if (b.isEmpty) return null;
    final exact = _index[b];
    if (exact != null) return exact;
    if (b.length >= 8) {
      Item? best;
      for (final i in items) {
        if (i.key.length >= 8 && b.contains(i.key)) {
          if (best == null || i.key.length > best.key.length) best = i;
        }
      }
      if (best != null) return best;
      final hits = items.where((i) => i.key.length >= 8 && i.key.contains(b)).toList();
      if (hits.length == 1) return hits.first;
    }
    return null;
  }

  ScanResult scan(String raw, {double qty = 1}) {
    final code = raw.trim();
    final it = find(code);
    if (it != null) {
      it.counted += qty;
      it.touched = true;
      it.lastScan = DateTime.now();
    } else {
      extras[code] = (extras[code] ?? 0) + qty;
    }
    _log.add(_Event(code, it, qty));
    if (_log.length > 500) _log.removeAt(0);
    _changed();
    return ScanResult(code, it, qty);
  }

  void undoLast() {
    if (_log.isEmpty) return;
    final e = _log.removeLast();
    if (e.item != null) {
      e.item!.counted = (e.item!.counted - e.qty).clamp(0, double.infinity).toDouble();
    } else {
      final v = (extras[e.code] ?? 0) - e.qty;
      if (v <= 0) {
        extras.remove(e.code);
      } else {
        extras[e.code] = v;
      }
    }
    _changed();
  }

  void setCounted(Item it, double v) {
    it.counted = v < 0 ? 0 : v;
    it.touched = true;
    it.lastScan = DateTime.now();
    _changed();
  }

  void setExtra(String code, double v) {
    if (v <= 0) {
      extras.remove(code);
    } else {
      extras[code] = v;
    }
    _changed();
  }
}
