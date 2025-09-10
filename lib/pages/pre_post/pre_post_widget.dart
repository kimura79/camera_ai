// === Crea immagine affiancata e salva in galleria ===
Future<void> _saveComparisonImage() async {
  if (preImage == null || postImage == null) return;

  final preBytes = await preImage!.readAsBytes();
  final postBytes = await postImage!.readAsBytes();
  final pre = img.decodeImage(preBytes);
  final post = img.decodeImage(postBytes);

  if (pre == null || post == null) return;

  final resizedPre = img.copyResize(pre, width: 1024, height: 1024);
  final resizedPost = img.copyResize(post, width: 1024, height: 1024);

  // 🔹 nuovo costruttore corretto
  final combined = img.Image(width: resizedPre.width * 2, height: resizedPre.height);

  // 🔹 usa compositeImage invece di copyInto
  img.compositeImage(combined, resizedPre, dstX: 0, dstY: 0);
  img.compositeImage(combined, resizedPost, dstX: resizedPre.width, dstY: 0);

  final jpg = img.encodeJpg(combined, quality: 90);

  // 🔹 serve anche il filename
  await PhotoManager.editor.saveImage(
    jpg,
    filename: "pre_post_${DateTime.now().millisecondsSinceEpoch}.jpg",
  );

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Immagine salvata in galleria")),
    );
  }
}
