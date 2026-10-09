import 'package:flutter/material.dart';
import 'main.dart';
import 'models.dart';
import 'report.dart';

class ReportView extends StatelessWidget {
  const ReportView({super.key});

  @override
  Widget build(BuildContext context) {
    if (!inv.hasData) return const Center(child: Text('Chưa có dữ liệu. Hãy nhập file tồn trước.'));
    final s = Summary.of(inv);
    final cs = Theme.of(context).colorScheme;

    return ListView(padding: const EdgeInsets.all(12), children: [
      // ---------- tiến độ ----------
      _Card(title: 'Tiến độ kiểm', children: [
        LinearProgressIndicator(value: s.progress, minHeight: 10, borderRadius: BorderRadius.circular(6)),
        const SizedBox(height: 6),
        Text('${s.skuInStockCounted}/${s.skuInStock} mã có tồn đã kiểm (${fmtPct(s.progress)})'),
        const Divider(),
        _row('Khớp', '${s.nMatch} mã', color: statusColor(ItemStatus.match)),
        _row('Thiếu', '${s.nShort} mã', color: statusColor(ItemStatus.short)),
        _row('Thừa', '${s.nOver} mã', color: statusColor(ItemStatus.over)),
        _row('Chưa kiểm', '${s.nNotCounted} mã', color: statusColor(ItemStatus.notCounted)),
        _row('Độ chính xác (khớp / đã kiểm)', fmtPct(s.accuracy)),
      ]),

      // ---------- tổng quan SL & GT ----------
      _Card(title: 'Tổng hợp tồn kho', children: [
        _head(),
        _grid('Tồn lý thuyết', fmtQty(s.sysQty), fmtMoney(s.sysVal)),
        _grid('Đã kiểm', fmtQty(s.countedQty), fmtMoney(s.countedVal)),
        const Divider(),
        _grid('Chênh lệch toàn kho', fmtSigned(s.diffQty), fmtMoneySigned(s.diffVal),
            color: s.diffQty == 0 ? statusColor(ItemStatus.match) : statusColor(s.diffQty < 0 ? ItemStatus.short : ItemStatus.over), bold: true),
        const SizedBox(height: 4),
        Text('Đã kiểm đạt ${fmtPct(s.qtyCoverage)} tổng lượng tồn lý thuyết (mã chưa kiểm tính = 0).',
            style: TextStyle(fontSize: 12, color: cs.outline)),
      ]),

      // ---------- phân tích chênh lệch ----------
      _Card(title: 'Phân tích chênh lệch', children: [
        _head(),
        _grid('Thừa (mã đã kiểm)', fmtQty(s.overQty), fmtMoney(s.overVal), color: statusColor(ItemStatus.over)),
        _grid('Thiếu (mã đã kiểm)', fmtQty(0 - s.shortQty), fmtMoney(0 - s.shortVal), color: statusColor(ItemStatus.short)),
        _grid('Chưa kiểm (tồn LT)', fmtQty(0 - s.uncountedQty), fmtMoney(0 - s.uncountedVal), color: statusColor(ItemStatus.notCounted)),
        const Divider(),
        _grid('Chênh lệch chỉ mã đã kiểm', fmtSigned(s.diffQtyCountedOnly), fmtMoneySigned(s.diffValCountedOnly), bold: true),
        if (s.nNoPrice > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ ${s.nNoPrice} mã đã kiểm nhưng không có giá BQ (tồn LT = 0) nên giá trị tính = 0.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
          ),
      ]),

      // ---------- theo ĐVT ----------
      _Card(title: 'Theo đơn vị tính', children: [
        const Text('Không cộng gộp PC / BỘ / CÁI / CHAI… vì khác đơn vị.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        for (final e in s.byUnit.entries)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${e.key}  (${e.value.sku} mã)'),
            subtitle: Text('Tồn ${fmtQty(e.value.sys)} • Kiểm ${fmtQty(e.value.counted)} • Lệch ${fmtSigned(e.value.diff)}'),
            children: [
              _row('Giá trị tồn LT', fmtMoney(e.value.sysVal)),
              _row('Giá trị đã kiểm', fmtMoney(e.value.countedVal)),
              _row('Chênh lệch giá trị', fmtMoneySigned(e.value.diffVal)),
            ],
          ),
      ]),

      // ---------- top chênh lệch ----------
      _Card(title: 'Top 10 chênh lệch giá trị lớn nhất', children: [
        if (s.topDiff.isEmpty) const Text('Chưa có chênh lệch.'),
        for (final it in s.topDiff.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${it.code} • Tồn ${fmtQty(it.sysQty)} → Kiểm ${fmtQty(it.counted)} (${statusLabel(it.status)})'),
            trailing: Text(fmtMoneySigned(it.diffValue), style: TextStyle(color: statusColor(it.status), fontWeight: FontWeight.bold)),
          ),
      ]),

      // ---------- ngoài danh sách ----------
      _Card(title: 'Hàng ngoài danh sách (${s.extraSku} mã • SL ${fmtQty(s.extraQty)})', children: [
        if (inv.extras.isEmpty) const Text('Không có.'),
        for (final e in inv.extras.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(e.key),
            trailing: Text(fmtQty(e.value), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
      ]),
      const SizedBox(height: 20),
    ]);
  }

  static Widget _row(String l, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l),
          Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  static Widget _head() => const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(flex: 4, child: SizedBox()),
          Expanded(flex: 3, child: Text('Số lượng', textAlign: TextAlign.right, style: TextStyle(fontSize: 12))),
          Expanded(flex: 4, child: Text('Giá trị', textAlign: TextAlign.right, style: TextStyle(fontSize: 12))),
        ]),
      );

  static Widget _grid(String l, String q, String v, {Color? color, bool bold = false}) {
    final st = TextStyle(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(flex: 4, child: Text(l, style: st)),
        Expanded(flex: 3, child: Text(q, textAlign: TextAlign.right, style: st)),
        Expanded(flex: 4, child: Text(v, textAlign: TextAlign.right, style: st)),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}
