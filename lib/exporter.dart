import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models.dart';
import 'report.dart';

TextCellValue _t(String s) => TextCellValue(s);
DoubleCellValue _d(double v) => DoubleCellValue(v);
IntCellValue _i(int v) => IntCellValue(v);

Future<String> exportAndShare(Inventory inv) async {
  final s = Summary.of(inv);
  final ex = Excel.createExcel();

  // ---- Tổng quan ----
  final a = ex['Tổng quan'];
  void kv(String k, CellValue v) => a.appendRow([_t(k), v]);
  a.appendRow([_t('BÁO CÁO KIỂM KÊ KHO')]);
  kv('Nguồn tồn lý thuyết', _t(inv.sourceName));
  kv('Xuất lúc', _t(DateTime.now().toString().substring(0, 19)));
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
  kv('Hàng ngoài danh sách - số mã', _i(s.extraSku));
  kv('Hàng ngoài danh sách - SL', _d(s.extraQty));

  // ---- Chi tiết ----
  final d = ex['Chi tiết'];
  d.appendRow([
    'Stt', 'Mã vật tư', 'Tên vật tư, hàng hóa', 'ĐVT', 'Tồn LT (SL)', 'Tồn LT (Giá trị)', 'Giá BQ',
    'Đã kiểm (SL)', 'Đã kiểm (Giá trị)', 'Chênh lệch SL', 'Chênh lệch giá trị', 'Trạng thái', 'Quét lần cuối'
  ].map(_t).toList());
  var n = 0;
  for (final it in inv.items) {
    n++;
    d.appendRow([
      _i(n), _t(it.code), _t(it.name), _t(it.unit), _d(it.sysQty), _d(it.sysValue), _d(it.avgPrice),
      _d(it.counted), _d(it.countedValue), _d(it.diff), _d(it.diffValue),
      _t(statusLabel(it.status)), _t(it.lastScan?.toString().substring(0, 19) ?? ''),
    ]);
  }

  // ---- Top chênh lệch ----
  final t = ex['Top chênh lệch'];
  t.appendRow(['Mã vật tư', 'Tên', 'ĐVT', 'Tồn LT', 'Đã kiểm', 'Chênh SL', 'Chênh giá trị', 'Trạng thái'].map(_t).toList());
  for (final it in s.topDiff) {
    t.appendRow([_t(it.code), _t(it.name), _t(it.unit), _d(it.sysQty), _d(it.counted), _d(it.diff), _d(it.diffValue), _t(statusLabel(it.status))]);
  }

  // ---- Theo ĐVT ----
  final u = ex['Theo ĐVT'];
  u.appendRow(['ĐVT', 'Số mã', 'Tồn LT (SL)', 'Tồn LT (Giá trị)', 'Đã kiểm (SL)', 'Đã kiểm (Giá trị)', 'Chênh SL', 'Chênh giá trị'].map(_t).toList());
  s.byUnit.forEach((k, v) {
    u.appendRow([_t(k), _i(v.sku), _d(v.sys), _d(v.sysVal), _d(v.counted), _d(v.countedVal), _d(v.diff), _d(v.diffVal)]);
  });

  // ---- Ngoài danh sách ----
  final e = ex['Ngoài danh sách'];
  e.appendRow(['Mã quét được', 'Số lượng'].map(_t).toList());
  inv.extras.forEach((k, v) => e.appendRow([_t(k), _d(v)]));

  ex.delete('Sheet1');
  ex.setDefaultSheet('Tổng quan');

  final bytes = ex.encode();
  if (bytes == null) throw Exception('Không tạo được file Excel');
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toString().substring(0, 16).replaceAll(RegExp(r'[: ]'), '-');
  final path = '${dir.path}/Bao_cao_kiem_kho_$stamp.xlsx';
  await File(path).writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(path)], subject: 'Báo cáo kiểm kho $stamp');
  return path;
}
