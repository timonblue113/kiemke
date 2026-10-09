import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';

final _qtyFmt = NumberFormat('#,##0.##', 'vi');
final _moneyFmt = NumberFormat('#,##0', 'vi');

String fmtQty(double v) => _qtyFmt.format(v);
String fmtMoney(double v) => _moneyFmt.format(v.round());
String fmtSigned(double v) => v > 0 ? '+${fmtQty(v)}' : fmtQty(v);
String fmtMoneySigned(double v) => v > 0 ? '+${fmtMoney(v)}' : fmtMoney(v);
String fmtPct(double v) => '${(v * 100).toStringAsFixed(1)}%';

Color statusColor(ItemStatus s) {
  switch (s) {
    case ItemStatus.match:
      return Colors.green.shade700;
    case ItemStatus.short:
      return Colors.red.shade700;
    case ItemStatus.over:
      return Colors.orange.shade800;
    case ItemStatus.notCounted:
      return Colors.blueGrey;
    case ItemStatus.noStock:
      return Colors.grey;
  }
}

String statusLabel(ItemStatus s) {
  switch (s) {
    case ItemStatus.match:
      return 'Khớp';
    case ItemStatus.short:
      return 'Thiếu';
    case ItemStatus.over:
      return 'Thừa';
    case ItemStatus.notCounted:
      return 'Chưa kiểm';
    case ItemStatus.noStock:
      return 'Không tồn';
  }
}

/// Đơn vị tính đang lọc (null = tất cả). Dùng chung cho tab Kiểm kê, Báo cáo và xuất file.
final unitFilter = ValueNotifier<String?>(null);

List<String> unitList(Inventory inv) {
  final set = <String>{for (final i in inv.items) unitKey(i.unit)};
  return set.toList()..sort();
}

class UnitStat {
  int sku = 0;
  double sys = 0, sysVal = 0, counted = 0, countedVal = 0;
  double get diff => counted - sys;
  double get diffVal => countedVal - sysVal;
}

class Summary {
  // số mã
  int skuInStock = 0; // mã có tồn lý thuyết > 0
  int skuInStockCounted = 0; // trong đó đã kiểm
  int skuTouched = 0; // tất cả mã đã kiểm (kể cả tồn 0)
  int nMatch = 0, nShort = 0, nOver = 0, nNotCounted = 0;
  int nNoPrice = 0; // mã đã kiểm nhưng không có giá BQ

  // số lượng / giá trị
  double sysQty = 0, sysVal = 0;
  double countedQty = 0, countedVal = 0;
  double overQty = 0, overVal = 0; // thừa (các mã đã kiểm)
  double shortQty = 0, shortVal = 0; // thiếu (các mã đã kiểm) - số dương
  double uncountedQty = 0, uncountedVal = 0; // tồn của mã chưa kiểm - số dương

  // ngoài danh sách
  int extraSku = 0;
  double extraQty = 0;

  final Map<String, UnitStat> byUnit = {};
  List<Item> topDiff = [];

  double get diffQty => countedQty - sysQty; // = over - short - uncounted
  double get diffVal => countedVal - sysVal;
  double get progress => skuInStock == 0 ? 0 : skuInStockCounted / skuInStock;
  double get accuracy => skuTouched == 0 ? 0 : nMatch / skuTouched; // % mã khớp
  double get qtyCoverage => sysQty == 0 ? 0 : countedQty / sysQty;

  /// Chênh lệch chỉ tính trên các mã đã kiểm (không tính mã chưa kiểm)
  double get diffQtyCountedOnly => overQty - shortQty;
  double get diffValCountedOnly => overVal - shortVal;

  static Summary of(Inventory inv, {String? unit}) {
    final s = Summary();
    final scope = unit == null ? inv.items : inv.items.where((i) => unitKey(i.unit) == unit).toList();
    for (final it in scope) {
      final u = s.byUnit.putIfAbsent(unitKey(it.unit), () => UnitStat());
      u.sku++;
      u.sys += it.sysQty;
      u.sysVal += it.sysValue;
      u.counted += it.counted;
      u.countedVal += it.countedValue;

      s.sysQty += it.sysQty;
      s.sysVal += it.sysValue;
      s.countedQty += it.counted;
      s.countedVal += it.countedValue;
      if (it.sysQty > 0) s.skuInStock++;
      if (it.touched) {
        s.skuTouched++;
        if (it.sysQty > 0) s.skuInStockCounted++;
        if (it.avgPrice == 0 && it.counted > 0) s.nNoPrice++;
      }

      switch (it.status) {
        case ItemStatus.match:
          s.nMatch++;
          break;
        case ItemStatus.short:
          s.nShort++;
          s.shortQty += -it.diff;
          s.shortVal += -it.diffValue;
          break;
        case ItemStatus.over:
          s.nOver++;
          s.overQty += it.diff;
          s.overVal += it.diffValue;
          break;
        case ItemStatus.notCounted:
          s.nNotCounted++;
          s.uncountedQty += it.sysQty;
          s.uncountedVal += it.sysValue;
          break;
        case ItemStatus.noStock:
          break;
      }
    }
    if (unit == null) {
      s.extraSku = inv.extras.length;
      s.extraQty = inv.extras.values.fold(0.0, (a, b) => a + b);
    }
    s.topDiff = scope.where((i) => i.diff != 0).toList()
      ..sort((a, b) => b.diffValue.abs().compareTo(a.diffValue.abs()));
    return s;
  }
}
