ElevatedButton(
  onPressed: () {
    if (preImage != null && postImage != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PrePostComparePage(
            preOverlay: preImage!,
            postOverlay: postImage!,
          ),
        ),
      );
    }
  },
  child: const Text("Confronta macchie"),
),
