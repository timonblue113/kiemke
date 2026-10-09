import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models.dart';
import 'report.dart';

TextCellValue _t(String s) => TextCellValue(s);
DoubleCellValue _d(double v) => DoubleCellValue(v);
IntCellValue _i(int v) => IntCellValue(v);

String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
String _now() => DateTime.now().toString().substring(0, 19);

Iterable<Item> _scope(Inventory inv, String? unit) =>
    unit == null ? inv.items : inv.items.where((i) => unitKey(i.unit) == unit);

Future<String> _shareExcel(Excel ex, String base) async {
  final bytes = ex.encode();
  if (bytes == null) throw Exception('Không tạo được file Excel');
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toString().substring(0, 16).replaceAll(RegExp(r'[: ]'), '-');
  final path = '${dir.path}/${base}_$stamp.xlsx';
  await File(path).writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(path)], subject: '$base $stamp');
  return path;
}

const _itemHead = [
  'Stt', 'Mã vật tư', 'Tên vật tư, hàng hóa', 'ĐVT', 'Tồn LT (SL)', 'Tồn LT (Giá trị)', 'Giá BQ',
  'Đã kiểm (SL)', 'Đã kiểm (Giá trị)', 'Chênh lệch SL', 'Chênh lệch giá trị', 'Trạng thái', 'Quét lần cuối'
];

List<CellValue?> _itemRow(int n, Item it) => [
      _i(n), _t(it.code), _t(it.name), _t(it.unit), _d(it.sysQty), _d(it.sysValue), _d(it.avgPrice),
      _d(it.counted), _d(it.countedValue), _d(it.diff), _d(it.diffValue),
      _t(statusLabel(it.status)), _t(it.lastScan?.toString().substring(0, 19) ?? ''),
    ];

void _totalRow(Sheet sh, List<Item> list) {
  double sq = 0, sv = 0, cq = 0, cv = 0;
  for (final it in list) {
    sq += it.sysQty;
    sv += it.sysValue;
    cq += it.counted;
    cv += it.countedValue;
  }
  sh.appendRow([
    null, _t('TỔNG CỘNG (${list.length} mã)'), null, null, _d(sq), _d(sv), null,
    _d(cq), _d(cv), _d(cq - sq), _d(cv - sv), null, null
  ]);
}

/// Báo cáo đầy đủ. [unit] != null -> chỉ riêng 1 đơn vị tính.
Future<String> exportAndShare(Inventory inv, {String? unit}) async {
  final s = Summary.of(inv, unit: unit);
  final items = _scope(inv, unit).toList();
  final ex = Excel.createExcel();

  // ---- Tổng quan ----
  final a = ex['Tổng quan'];
  void kv(String k, CellValue v) => a.appendRow([_t(k), v]);
  a.appendRow([_t('BÁO CÁO KIỂM KÊ KHO')]);
  kv('Phạm vi', _t(unit == null ? 'Tất cả đơn vị tính' : 'Đơn vị tính: $unit'));
  kv('Nguồn tồn lý thuyết', _t(inv.sourceName));
  kv('Xuất lúc', _t(_now()));
  a.appendRow([]);
  a.appendRow([_t('TIẾN ĐỘ')]);
  kv('Số mã có tồn lý thuyết', _i(s.skuInStock));
  kv('Số mã đã kiểm (có tồn)', _i(s.skuInStockCounted));
  kv('Tiến độ kiểm (% mã)', _t(fmtPct(s.progress)));
  kv('Mã khớp', _i(s.nMatch));
  kv('Mã thiếu', _i(s.nShort));
  kv('Mã thừa', _i(s.nOver));
  kv('Mã chưa kiểm', _i(s.nNotCounted));
  kv('Độ chính xác (khớp / đã kiểm)', _t(fmtPct(s.accuracy)));
  a.appendRow([]);
  a.appendRow([_t('TỔNG HỢP SỐ LƯỢNG & GIÁ TRỊ')]);
  kv('Tồn lý thuyết - SL', _d(s.sysQty));
  kv('Tồn lý thuyết - Giá trị', _d(s.sysVal));
  kv('Đã kiểm - SL', _d(s.countedQty));
  kv('Đã kiểm - Giá trị (SL x Giá BQ)', _d(s.countedVal));
  kv('Chênh lệch toàn kho - SL (chưa kiểm tính = 0)', _d(s.diffQty));
  kv('Chênh lệch toàn kho - Giá trị', _d(s.diffVal));
  kv('Thừa (mã đã kiểm) - SL', _d(s.overQty));
  kv('Thừa (mã đã kiểm) - Giá trị', _d(s.overVal));
  kv('Thiếu (mã đã kiểm) - SL', _d(s.shortQty));
  kv('Thiếu (mã đã kiểm) - Giá trị', _d(s.shortVal));
  kv('Chưa kiểm - SL tồn', _d(s.uncountedQty));
  kv('Chưa kiểm - Giá trị tồn', _d(s.uncountedVal));
  if (unit == null) {
    kv('Hàng ngoài danh sách - số mã', _i(s.extraSku));
    kv('Hàng ngoài danh sách - SL', _d(s.extraQty));
  }

  // ---- Theo ĐVT ----
  final u = ex['Theo ĐVT'];
  u.appendRow(['ĐVT', 'Số mã', 'Tồn LT (SL)', 'Tồn LT (Giá trị)', 'Đã kiểm (SL)', 'Đã kiểm (Giá trị)', 'Chênh SL', 'Chênh giá trị'].map(_t).toList());
  s.byUnit.forEach((k, v) {
    u.appendRow([_t(k), _i(v.sku), _d(v.sys), _d(v.sysVal), _d(v.counted), _d(v.countedVal), _d(v.diff), _d(v.diffVal)]);
  });

  // ---- Chi tiết ----
  final d = ex['Chi tiết'];
  d.appendRow(_itemHead.map(_t).toList());
  var n = 0;
  for (final it in items) {
    d.appendRow(_itemRow(++n, it));
  }
  _totalRow(d, items);

  // ---- Top chênh lệch ----
  final t = ex['Top chênh lệch'];
  t.appendRow(['Mã vật tư', 'Tên', 'ĐVT', 'Tồn LT', 'Đã kiểm', 'Chênh SL', 'Chênh giá trị', 'Trạng thái'].map(_t).toList());
  for (final it in s.topDiff) {
    t.appendRow([_t(it.code), _t(it.name), _t(it.unit), _d(it.sysQty), _d(it.counted), _d(it.diff), _d(it.diffValue), _t(statusLabel(it.status))]);
  }

  // ---- Ngoài danh sách ----
  if (unit == null) {
    final e = ex['Ngoài danh sách'];
    e.appendRow(['Mã quét được', 'Số lượng'].map(_t).toList());
    inv.extras.forEach((k, v) => e.appendRow([_t(k), _d(v)]));
  }

  ex.delete('Sheet1');
  ex.setDefaultSheet('Tổng quan');
  return _shareExcel(ex, unit == null ? 'Bao_cao_kiem_kho' : 'Bao_cao_kiem_kho_${_safe(unit)}');
}

/// Chỉ danh sách đã kiểm (+ chưa kiểm + ngoài danh sách). [unit] != null -> riêng 1 ĐVT.
Future<String> exportChecked(Inventory inv, {String? unit}) async {
  final all = _scope(inv, unit).toList();
  final checked = all.where((i) => i.touched).toList();
  final pending = all.where((i) => i.status == ItemStatus.notCounted).toList();
  final ex = Excel.createExcel();

  final c = ex['Đã kiểm'];
  c.appendRow([_t('DANH SÁCH ĐÃ KIỂM${unit == null ? '' : ' - ĐVT $unit'}'), null, null, _t('Xuất lúc: ${_now()}')]);
  c.appendRow(_itemHead.map(_t).toList());
  var n = 0;
  for (final it in checked) {
    c.appendRow(_itemRow(++n, it));
  }
  _totalRow(c, checked);

  final p = ex['Chưa kiểm'];
  p.appendRow(_itemHead.map(_t).toList());
  n = 0;
  for (final it in pending) {
    p.appendRow(_itemRow(++n, it));
  }
  _totalRow(p, pending);

  if (unit == null) {
    final e = ex['Ngoài danh sách'];
    e.appendRow(['Mã quét được', 'Số lượng'].map(_t).toList());
    inv.extras.forEach((k, v) => e.appendRow([_t(k), _d(v)]));
  }

  ex.delete('Sheet1');
  ex.setDefaultSheet('Đã kiểm');
  return _shareExcel(ex, unit == null ? 'Danh_sach_da_kiem' : 'Danh_sach_da_kiem_${_safe(unit)}');
}
