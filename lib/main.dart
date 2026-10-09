import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'exporter.dart';
import 'importer.dart';
import 'models.dart';
import 'report.dart';
import 'report_page.dart';
import 'scan_page.dart';

final inv = Inventory();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await inv.load();
  runApp(const App());
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

/// Hộp thoại nhập số. Trả về null nếu hủy.
Future<double?> askNumber(BuildContext c, String title, double initial, {String? hint}) {
  final ctl = TextEditingController(text: initial == 0 ? '' : fmtQty(initial).replaceAll('.', ''));
  return showDialog<double>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: hint ?? 'Số lượng'),
        onSubmitted: (v) => Navigator.pop(c, double.tryParse(v.replaceAll(',', '.'))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
        FilledButton(
          onPressed: () => Navigator.pop(c, double.tryParse(ctl.text.replaceAll(',', '.'))),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext c, String title, String msg) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đồng ý')),
      ],
    ),
  );
  return r ?? false;
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kiểm kho',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  Future<void> _import() async {
    if (inv.hasAnyCount) {
      final ok = await confirm(context, 'Nhập file mới?', 'Số liệu đã kiểm hiện tại sẽ bị xóa và thay bằng danh sách tồn mới.');
      if (!ok) return;
    }
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) {
      if (mounted) toast(context, 'Không đọc được file');
      return;
    }
    try {
      final r = importFile(f.name, f.bytes!);
      inv.setItems(r.items, f.name);
      if (mounted) toast(context, 'Đã nhập ${r.items.length} mã từ ${r.info}');
    } catch (e) {
      if (mounted) toast(context, 'Lỗi nhập file: $e');
    }
  }

  Future<void> _export() async {
    if (!inv.hasData) {
      toast(context, 'Chưa có dữ liệu');
      return;
    }
    try {
      await exportAndShare(inv);
    } catch (e) {
      if (mounted) toast(context, 'Lỗi xuất file: $e');
    }
  }

  Future<void> _reset() async {
    if (await confirm(context, 'Xóa số liệu kiểm?', 'Giữ lại danh sách tồn, chỉ xóa số lượng đã kiểm.')) {
      inv.resetCounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: inv,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tab == 0 ? 'Kiểm kê' : 'Báo cáo'),
          actions: [
            IconButton(tooltip: 'Nhập file tồn', icon: const Icon(Icons.upload_file), onPressed: _import),
            IconButton(tooltip: 'Xuất Excel', icon: const Icon(Icons.ios_share), onPressed: _export),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'undo') inv.undoLast();
                if (v == 'reset') _reset();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'undo', enabled: inv.canUndo, child: const Text('Hoàn tác lần quét cuối')),
                const PopupMenuItem(value: 'reset', child: Text('Xóa số liệu đã kiểm')),
              ],
            ),
          ],
        ),
        body: tab == 0 ? ItemsTab(onImport: _import) : const ReportView(),
        floatingActionButton: tab == 0 && inv.hasData
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanPage())),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Quét mã'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Kiểm kê'),
            NavigationDestination(icon: Icon(Icons.assessment_outlined), label: 'Báo cáo'),
          ],
        ),
      ),
    );
  }
}

class ItemsTab extends StatefulWidget {
  const ItemsTab({super.key, required this.onImport});
  final VoidCallback onImport;
  @override
  State<ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<ItemsTab> {
  String q = '';
  ItemStatus? filter;

  static const _filters = <ItemStatus?, String>{
    null: 'Tất cả',
    ItemStatus.notCounted: 'Chưa kiểm',
    ItemStatus.match: 'Khớp',
    ItemStatus.short: 'Thiếu',
    ItemStatus.over: 'Thừa',
  };

  @override
  Widget build(BuildContext context) {
    if (!inv.hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.table_chart_outlined, size: 64),
            const SizedBox(height: 12),
            const Text('Chưa có danh sách tồn lý thuyết.\nNhập file Excel (.xlsx) hoặc CSV có cột:\nMã vật tư | Tên | ĐVT | Số lượng | Giá trị',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: widget.onImport, icon: const Icon(Icons.upload_file), label: const Text('Nhập file tồn')),
          ]),
        ),
      );
    }
    final nq = q.trim().toLowerCase();
    final list = inv.items.where((i) {
      if (filter != null && i.status != filter) return false;
      if (filter == null && i.status == ItemStatus.noStock && nq.isEmpty) return false;
      if (nq.isEmpty) return true;
      return i.name.toLowerCase().contains(nq) || i.code.toLowerCase().contains(nq) || i.key.contains(normCode(nq));
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm mã / tên vật tư', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final e in _filters.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(label: Text(e.value), selected: filter == e.key, onSelected: (_) => setState(() => filter = e.key)),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 90),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final it = list[i];
            final c = statusColor(it.status);
            return ListTile(
              dense: true,
              isThreeLine: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: c,
                child: Text(statusLabel(it.status).substring(0, 1), style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              title: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${it.code} • ${it.unit}\nTồn ${fmtQty(it.sysQty)}  |  Kiểm ${fmtQty(it.counted)}  |  Lệch ${fmtSigned(it.diff)}'),
              trailing: it.diff == 0 ? null : Text(fmtMoneySigned(it.diffValue), style: TextStyle(color: c, fontWeight: FontWeight.w600)),
              onTap: () async {
                final v = await askNumber(context, it.name, it.counted, hint: 'Số lượng thực tế (đặt lại)');
                if (v != null) inv.setCounted(it, v);
              },
            );
          },
        ),
      ),
    ]);
  }
}
