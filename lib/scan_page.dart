import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'feedback.dart';
import 'main.dart';
import 'models.dart';
import 'report.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  static const _gChannel = MethodChannel('kiemkho/gscan');

  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 300,
    cameraResolution: const Size(1920, 1080), // độ phân giải cao -> đọc mã nhỏ/mờ tốt hơn
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf,
      BarcodeFormat.codabar,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  ScanResult? last;
  String? _lastRaw;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool askQty = false;
  bool busy = false;
  bool torch = false;
  double zoom = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // giữ màn hình sáng khi đang kiểm
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (busy) return;
    String? raw;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        raw = v;
        break;
      }
    }
    if (raw == null) return;
    final now = DateTime.now();
    // chống quét trùng liên tục cùng 1 mã trong 2 giây
    if (raw == _lastRaw && now.difference(_lastAt).inMilliseconds < 2000) return;
    _lastRaw = raw;
    _lastAt = now;
    await _handle(raw);
  }

  Future<void> _handle(String raw) async {
    var qty = 1.0;
    if (askQty) {
      busy = true;
      final q = await askNumber(context, 'Số lượng cho mã $raw', 1);
      busy = false;
      if (q == null || q <= 0) return;
      qty = q;
    }
    _apply(raw, qty);
  }

  void _apply(String raw, double qty) {
    if (!mounted) return;
    final r = inv.scan(raw, qty: qty);
    final it = r.item;
    // đúng mã & chưa vượt tồn -> ting; ngoài danh sách hoặc vượt tồn lý thuyết -> cảnh báo
    if (it != null && it.counted <= it.sysQty) {
      scanFeedbackOk();
    } else {
      scanFeedbackWarn();
    }
    setState(() => last = r);
  }

  /// Quét 1 mã bằng Google Code Scanner (màn hình quét của Google Play Services)
  Future<void> _googleScan() async {
    busy = true;
    try {
      await controller.stop();
      final v = await _gChannel.invokeMethod<String>('scan');
      if (v != null && v.isNotEmpty) await _handle(v);
    } on PlatformException catch (e) {
      if (mounted) toast(context, 'Google Scanner lỗi: ${e.message ?? e.code}');
    } on MissingPluginException {
      if (mounted) toast(context, 'Máy chưa hỗ trợ Google Scanner');
    } finally {
      busy = false;
      if (mounted) {
        try {
          await controller.start();
        } catch (_) {}
      }
    }
  }

  Future<void> _manual() async {
    busy = true;
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nhập mã thủ công'),
        content: TextField(controller: ctl, autofocus: true, textCapitalization: TextCapitalization.characters, onSubmitted: (v) => Navigator.pop(c, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Thêm')),
        ],
      ),
    );
    busy = false;
    if (code != null && code.trim().isNotEmpty) _apply(code, 1);
  }

  Future<void> _setQty() async {
    final r = last;
    if (r == null) return;
    busy = true;
    final cur = r.item?.counted ?? inv.extras[r.code] ?? 0;
    final v = await askNumber(context, 'Đặt lại số lượng', cur);
    busy = false;
    if (v == null) return;
    if (r.item != null) {
      inv.setCounted(r.item!, v);
    } else {
      inv.setExtra(r.code, v);
    }
    setState(() {});
  }

  /// Mã vạch lạ -> chọn mã vật tư tương ứng; các lần quét sau tự nhận.
  Future<void> _assign() async {
    final r = last;
    if (r == null || r.item != null) return;
    busy = true;
    final it = await pickItem(context);
    busy = false;
    if (it == null) return;
    inv.assignAlias(r.code, it);
    scanFeedbackOk();
    setState(() => last = ScanResult(r.code, it, r.qty));
    if (mounted) toast(context, 'Đã gán mã ${r.code} → ${it.code}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: inv,
        builder: (context, _) {
          final s = Summary.of(inv);
          return Stack(children: [
            Positioned.fill(child: MobileScanner(controller: controller, onDetect: _onDetect)),
            Center(
              child: Container(
                width: 280,
                height: 160,
                decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2), borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SafeArea(
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(children: [
                  IconButton(color: Colors.white, icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Text('Đã kiểm ${s.skuInStockCounted}/${s.skuInStock} mã (${fmtPct(s.progress)})', style: const TextStyle(color: Colors.white)),
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Bật/tắt tiếng và rung',
                    icon: Icon(feedbackEnabled ? Icons.volume_up : Icons.volume_off),
                    onPressed: () => setState(() => feedbackEnabled = !feedbackEnabled),
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Quét bằng Google Scanner',
                    icon: const Icon(Icons.g_mobiledata, size: 32),
                    onPressed: _googleScan,
                  ),
                  IconButton(
                    color: Colors.white,
                    icon: Icon(torch ? Icons.flash_on : Icons.flash_off),
                    onPressed: () async {
                      await controller.toggleTorch();
                      setState(() => torch = !torch);
                    },
                  ),
                  IconButton(color: Colors.white, icon: const Icon(Icons.keyboard), tooltip: 'Nhập mã', onPressed: _manual),
                ]),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.zoom_out, color: Colors.white),
                  Expanded(
                    child: Slider(
                      value: zoom,
                      onChanged: (v) {
                        setState(() => zoom = v);
                        controller.setZoomScale(v);
                      },
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white),
                  const SizedBox(width: 10),
                ]),
              ),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomCard(context)),
          ]);
        },
      ),
    );
  }

  Widget _bottomCard(BuildContext context) {
    final r = last;
    Widget body;
    if (r == null) {
      body = const Text('Hướng camera vào mã vạch (mỗi lần quét +1). Biểu tượng G = quét bằng Google Scanner.');
    } else if (r.item == null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('⚠ Ngoài danh sách tồn', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
        Text(r.code, style: const TextStyle(fontSize: 18)),
        Text('Đã ghi nhận: ${fmtQty(inv.extras[r.code] ?? 0)}  •  Nếu là hàng trong kho, bấm "Gán mã vật tư".'),
      ]);
    } else {
      final it = r.item!;
      final c = statusColor(it.status);
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
        Text('${it.code} • ${it.unit}'),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _stat('Tồn LT', fmtQty(it.sysQty), null),
          _stat('Đã kiểm', fmtQty(it.counted), c),
          _stat('Lệch', fmtSigned(it.diff), c),
          _stat('Trạng thái', statusLabel(it.status), c),
        ]),
        if (it.diff > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('⚠ Vượt tồn lý thuyết ${fmtQty(it.diff)} ${it.unit}', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
          ),
      ]);
    }
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: body),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton.icon(onPressed: inv.canUndo ? inv.undoLast : null, icon: const Icon(Icons.undo), label: const Text('Hoàn tác')),
                  OutlinedButton.icon(onPressed: r == null ? null : _setQty, icon: const Icon(Icons.edit), label: const Text('Sửa SL')),
                  if (r != null && r.item == null)
                    FilledButton.tonalIcon(onPressed: _assign, icon: const Icon(Icons.link), label: const Text('Gán mã vật tư')),
                ]),
              ),
              Column(children: [
                const Text('Hỏi SL', style: TextStyle(fontSize: 11)),
                Switch(value: askQty, onChanged: (v) => setState(() => askQty = v)),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String l, String v, Color? c) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c)),
      ]);
}
