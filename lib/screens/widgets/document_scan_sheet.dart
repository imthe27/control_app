import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:control_app/utils/document_parsers.dart';

/// Review sheet for a scanned document.
///
/// **This is the only thing standing between OCR and the worker record.**
/// Nothing in the scanner writes to a controller; the parsers produce
/// candidates, this sheet collects per-field confirmation, and the caller
/// applies what comes back. Keep that arrangement — a parser of photographed
/// text is wrong often enough that any direct path would eventually put a
/// stranger's CURP on a worker.
///
/// Returns the confirmed values, or `null` when the user cancels. An empty map
/// is a real answer: it means they ticked nothing.
Future<Map<WorkerField, String>?> showDocumentScanSheet({
  required BuildContext context,
  required ScanResult result,
  required Map<WorkerField, String> current,
}) {
  return showModalBottomSheet<Map<WorkerField, String>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _DocumentScanSheet(result: result, current: current),
  );
}

class _DocumentScanSheet extends StatefulWidget {
  final ScanResult result;
  final Map<WorkerField, String> current;

  const _DocumentScanSheet({required this.result, required this.current});

  @override
  State<_DocumentScanSheet> createState() => _DocumentScanSheetState();
}

class _DocumentScanSheetState extends State<_DocumentScanSheet> {
  /// Which fields the user has confirmed.
  ///
  /// Seeded from [ScannedField.preTicked], which is true only when a check
  /// digit verified. Everything else starts unticked — including every name and
  /// address, which have no check digit at all. A field that merely looks
  /// well-shaped is not evidence: `5` and `S` produce equally plausible
  /// nonsense, and the user is the one who can see the document.
  late final Map<WorkerField, bool> _ticked = {
    for (final f in widget.result.fields) f.target: f.preTicked,
  };

  static const _blue = Color(0xFF1C1CF0);

  bool _willOverwrite(ScannedField f) {
    final existing = widget.current[f.target]?.trim() ?? '';
    return existing.isNotEmpty && existing != f.value;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.document_scanner_outlined, color: _blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.kind.label.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: r.isEmpty ? _emptyState(r) : _fieldList(r),
              ),
              const Divider(height: 1),
              _actions(r),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown when the parsers found nothing.
  ///
  /// The raw text is offered rather than a dead end: a partial read the user can
  /// copy from is still useful, and — more importantly — a sheet that opens
  /// empty with no explanation is indistinguishable from a broken feature. If
  /// OCR genuinely returned nothing, say that too.
  Widget _emptyState(ScanResult r) {
    final text = r.rawText.trim();
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Text(
          text.isEmpty
              ? 'No se leyó texto en la imagen. Intenta con más luz, sin '
                  'sombras y con el documento plano.'
              : 'No se reconocieron datos en este documento. Este es el texto '
                  'que sí se leyó:',
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _blue),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('COPIAR TEXTO'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Texto copiado')),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _fieldList(ScanResult r) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      children: [
        Text(
          'Revisa cada dato antes de aplicarlo. Solo se aplican los que marques.',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(height: 8),
        ...r.fields.map(_fieldRow),
        if (r.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...r.notes.map((n) => _note(n, Icons.info_outline, Colors.orange)),
        ],
      ],
    );
  }

  Widget _fieldRow(ScannedField f) {
    final existing = widget.current[f.target]?.trim() ?? '';
    final overwrite = _willOverwrite(f);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _ticked[f.target] ?? false,
                  activeColor: _blue,
                  onChanged: (v) =>
                      setState(() => _ticked[f.target] = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.label,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4)),
                        const SizedBox(height: 4),
                        // The scanned value, always shown.
                        Text(f.value,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Side by side with what is already typed, whenever applying would
            // replace something. Losing a half-typed name to a scan is the
            // failure that kills adoption of a feature like this, so the
            // existing value is never off-screen at the moment of the decision.
            if (overwrite)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note,
                              size: 16, color: Colors.orange),
                          const SizedBox(width: 6),
                          Text('REEMPLAZA LO CAPTURADO',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange[900])),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(existing,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[800],
                              decoration: TextDecoration.lineThrough)),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 6),
              child: _status(f),
            ),
            ...f.notes.map((n) => Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _note(n, Icons.warning_amber_rounded, Colors.orange),
                )),
          ],
        ),
      ),
    );
  }

  /// ⚠ **Never the word "verificado".**
  ///
  /// A check digit proves a CURP is internally consistent. It proves nothing
  /// about whose it is, and a scan cannot tell whether this document belongs to
  /// the worker being edited. "Formato válido" is the strongest honest claim.
  Widget _status(ScannedField f) {
    final check = f.check;
    if (check == null) {
      return _hint('Sin dígito verificador — confirma contra el documento.',
          Icons.remove_circle_outline, Colors.grey);
    }
    if (check.checkDigitOk == true) {
      return _hint('Formato válido.', Icons.check_circle_outline, Colors.green);
    }
    return _hint('El formato no cuadra — revísalo con calma.',
        Icons.error_outline, Colors.red);
  }

  Widget _hint(String text, IconData icon, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          ),
        ],
      );

  Widget _note(String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: _hint(text, icon, color),
      );

  Widget _actions(ScanResult r) {
    final count = _ticked.values.where((v) => v).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: r.isEmpty || count == 0
                  ? null
                  : () => Navigator.pop(context, {
                        for (final f in r.fields)
                          if (_ticked[f.target] == true) f.target: f.value,
                      }),
              child: Text(count == 0 ? 'APLICAR' : 'APLICAR ($count)'),
            ),
          ),
        ],
      ),
    );
  }
}
