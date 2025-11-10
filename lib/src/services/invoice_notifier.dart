import 'dart:async';

/// Simple singleton notifier to broadcast invoice changes within the app.
/// Now transports the full Map<String, dynamic> of the saved invoice when available.
class InvoiceNotifier {
  InvoiceNotifier._internal();

  static final InvoiceNotifier instance = InvoiceNotifier._internal();

  final StreamController<Map<String, dynamic>?> _controller = StreamController<Map<String, dynamic>?>.broadcast();

  Stream<Map<String, dynamic>?> get stream => _controller.stream;

  void notify([Map<String, dynamic>? invoice]) {
    try {
      _controller.add(invoice);
    } catch (_) {}
  }

  void dispose() {
    _controller.close();
  }
}
