import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

class ChatScreen extends StatefulWidget {
  final String name;

  const ChatScreen({super.key, required this.name});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> messages = [
    {'text': 'Hola, ¿todo bien?', 'sent': true, 'time': '09:10 AM'},
    {'text': 'Sí, terminando aquí.', 'sent': false, 'time': '09:12 AM'},
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage({String? text, File? image, File? pdf}) {
  if (text == null && image == null && pdf == null) return;

  setState(() {
    messages.add({
      'text': text,
      'image': image,
      'pdf': pdf,
      'sent': true,
      'time': TimeOfDay.now().format(context),
    });
  });

  _controller.clear();
  Future.delayed(const Duration(milliseconds: 100), () {
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  });
}

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      _sendMessage(image: File(picked.path));
    }
  }

  Future<void> _pickPDF() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
  if (result != null && result.files.single.path != null) {
    File pdfFile = File(result.files.single.path!);
    _sendMessage(pdf: pdfFile);
  }
}


  Widget _buildMessage(Map<String, dynamic> msg) {
  final alignment = msg['sent'] ? Alignment.centerRight : Alignment.centerLeft;
  final color = msg['sent'] ? Colors.green[200] : Colors.grey[300];

  return Align(
    alignment: alignment,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment:
            msg['sent'] ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (msg['image'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(msg['image'], height: 150),
            ),
          if (msg['pdf'] != null)
            GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(pdfFile: msg['pdf'])));
              },
              child: Container(
                color: Colors.grey[200],
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.picture_as_pdf, color: Colors.red),
                    SizedBox(width: 8),
                    Text("PDF Document"),
                  ],
                ),
              ),
            ),
          if (msg['text'] != null) Text(msg['text']),
          Text(msg['time'],
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: messages.length,
              itemBuilder: (context, index) => _buildMessage(messages[index]),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo),
                  onPressed: _pickImage,
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  onPressed: _pickPDF,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendMessage(text: _controller.text.trim()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PdfViewerScreen extends StatelessWidget {
  final File pdfFile;

  const PdfViewerScreen({super.key, required this.pdfFile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Viewer')),
      body: PDFView(
        filePath: pdfFile.path,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
      ),
    );
  }
}
