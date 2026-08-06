import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

/// Does `Context.pageNumber` / `pagesCount` run document-wide, or restart for
/// every `MultiPage`?
///
/// This matters because the whole-bitácora PDF is one `pw.Document` holding a
/// cover `pw.Page` plus one `pw.MultiPage` per note. If numbering restarted per
/// MultiPage, every note would begin again at "Página 1 de 1" and the document
/// would be useless as a record.
///
/// Reading the source says document-wide — `pageNumber` is
/// `document.pdfPageList.pages.indexOf(page) + 1`, `pagesCount` is that list's
/// length. Running it turned up a wrinkle the source reading did not: the
/// footer builder is invoked TWICE per page.
void main() {
  test('page numbers run continuously across multiple MultiPages', () async {
    final seen = <String>[];

    final doc = pw.Document();

    // Cover sheet, as in buildLogbookPdf. A plain Page has no footer.
    doc.addPage(pw.Page(build: (context) => pw.Text('cover')));

    // Three notes, each its own MultiPage, each with the real footer's shape.
    for (var i = 0; i < 3; i++) {
      doc.addPage(
        pw.MultiPage(
          footer: (context) {
            seen.add('${context.pageNumber}/${context.pagesCount}');
            return pw.SizedBox();
          },
          build: (context) => [pw.Text('note $i')],
        ),
      );
    }

    await doc.save();

    // Six invocations for three footers. MultiPage calls the builder once
    // during layout, purely to measure the footer's height — at that moment
    // only the pages generated so far exist, so pagesCount is short (2/2, 3/3,
    // 4/4). It calls it again in postProcess(), which is what actually paints,
    // and by then every page exists.
    //
    // ⚠ The consequence for anything written into a header or footer builder:
    // it must be PURE. A counter, a list append, or any other side effect runs
    // twice per page and half the time sees an incomplete document.
    expect(seen.length, 6, reason: 'footer builder runs twice per page');

    // What actually reaches the paper is the second pass. Numbering continues
    // 2,3,4 across separate MultiPages rather than restarting at 1 per note,
    // and the total is the document's 4 rather than each MultiPage's own.
    expect(seen.sublist(3), ['2/4', '3/4', '4/4']);
  });
}
