import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'models.dart';

class ImportResult {
  ImportResult(this.items, this.info);
  final List<Item> items;
  final String info;
}

ImportResult importFile(String fileName, Uint8List bytes) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.xlsx')) return _fromXlsx(bytes);
  if (lower.endsWith('.csv') || lower.endsWith('.txt') || lower.endsWith('.tsv')) {
    final rows = parseCsv(utf8.decode(bytes, allowMalformed: true));
    final items = _parseTable(rows);
    if (items == null || items.isEmpty) throw const FormatException('Không tìm thấy dòng tiêu đề "Mã vật tư" / "Số lượng" trong file CSV.');
    return ImportResult(items, 'CSV');
  }
  throw const FormatException('Chỉ hỗ trợ .xlsx hoặc .csv (file .xls cũ hãy lưu lại thành .xlsx).');
}

ImportResult _fromXlsx(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  for (final name in excel.tables.keys) {
    final sheet = excel.tables[name]!;
    final rows = sheet.rows.map((r) => r.map(_cellStr).toList()).toList();
    final items = _parseTable(rows);
    if (items != null && items.isNotEmpty) return ImportResult(items, 'sheet "$name"');
  }
  throw const FormatException('Không sheet nào có dòng tiêu đề chứa "Mã vật tư" và "Số lượng".');
}

String _cellStr(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is TextCellValue) return v.value.toString();
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) return v.value.toString();
  return v.toString();
}

/// Đọc số kiểu VN/US: "1.234,5" "1,234.5" "1234.5" "1 234".
double parseNum(String s) {
  var t = s.trim().replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return 0;
  final hasC = t.contains(','), hasD = t.contains('.');
  if (hasC && hasD) {
    if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '');
    }
  } else if (hasC) {
    t = RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(t) ? t.replaceAll(',', '') : t.replaceAll(',', '.');
  } else if (hasD && '.'.allMatches(t).length > 1) {
    t = t.replaceAll('.', '');
  }
  return double.tryParse(t) ?? 0;
}

List<Item>? _parseTable(List<List<String>> rows) {
  // 1. tìm dòng tiêu đề: có ô bắt đầu bằng "mã" VÀ ô "số lượng"
  int h = -1;
  for (var i = 0; i < rows.length && i < 60; i++) {
    final low = rows[i].map((c) => c.trim().toLowerCase()).toList();
    final hasCode = low.any((c) => c.startsWith('mã') && c.length <= 25);
    final hasQty = low.any((c) => c.contains('số lượng') || c == 'sl');
    if (hasCode && hasQty) {
      h = i;
      break;
    }
  }
  if (h < 0) return null;

  final head = rows[h].map((c) => c.trim().toLowerCase()).toList();
  int first(bool Function(String) t) {
    for (var i = 0; i < head.length; i++) {
      if (t(head[i])) return i;
    }
    return -1;
  }

  int last(bool Function(String) t) {
    for (var i = head.length - 1; i >= 0; i--) {
      if (t(head[i])) return i;
    }
    return -1;
  }

  final cCode = first((s) => s.startsWith('mã') && s.length <= 25);
  final cName = first((s) => s.contains('tên'));
  final cUnit = first((s) => s == 'đvt' || s.contains('đơn vị'));
  final cQty = last((s) => s.contains('số lượng') || s == 'sl'); // lấy cột cuối = cuối kỳ
  final cVal = last((s) => s.contains('giá trị') || s.contains('thành tiền'));
  final cAvg = first((s) => s.contains('giá bq') || s.contains('bình quân') || s.contains('đơn giá'));

  String cell(List<String> r, int c) => (c < 0 || c >= r.length) ? '' : r[c].trim();

  final map = <String, Item>{};
  for (var i = h + 1; i < rows.length; i++) {
    final r = rows[i];
    final code = cell(r, cCode);
    if (code.isEmpty) continue;
    final name = cell(r, cName);
    if (name.toLowerCase().contains('tổng cộng')) continue;
    final qty = parseNum(cell(r, cQty));
    var val = parseNum(cell(r, cVal));
    final lp = parseNum(cell(r, cAvg));
    if (cVal < 0 && lp > 0) val = qty * lp;

    final k = normCode(code);
    final old = map[k];
    if (old != null) {
      old.sysQty += qty; // trùng mã -> cộng dồn
      old.sysValue += val;
    } else {
      map[k] = Item(code: code, name: name, unit: cell(r, cUnit), sysQty: qty, sysValue: val, listPrice: lp);
    }
  }
  return map.values.toList();
}

List<List<String>> parseCsv(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final sample = text.length > 3000 ? text.substring(0, 3000) : text;
  String delim = ',';
  var best = -1;
  for (final d in [',', ';', '\t']) {
    final n = d.allMatches(sample).length;
    if (n > best) {
      best = n;
      delim = d;
    }
  }
  final rows = <List<String>>[];
  var row = <String>[];
  final sb = StringBuffer();
  var inQ = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQ) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        sb.write(ch);
      }
    } else if (ch == '"') {
      inQ = true;
    } else if (ch == delim) {
      row.add(sb.toString());
      sb.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(sb.toString());
      sb.clear();
      rows.add(row);
      row = <String>[];
    } else {
      sb.write(ch);
    }
  }
  if (sb.isNotEmpty || row.isNotEmpty) {
    row.add(sb.toString());
    rows.add(row);
  }
  return rows;
}
