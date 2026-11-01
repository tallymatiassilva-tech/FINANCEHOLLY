import 'package:flutter/material.dart';

Future<T?> showDialogWithControllers<T>({
  required BuildContext context,
  required Iterable<TextEditingController> controllers,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => _DialogControllerOwner(
      controllers: List<TextEditingController>.of(controllers),
      child: builder(dialogContext),
    ),
  );
}

class _DialogControllerOwner extends StatefulWidget {
  const _DialogControllerOwner({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_DialogControllerOwner> createState() => _DialogControllerOwnerState();
}

class _DialogControllerOwnerState extends State<_DialogControllerOwner> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
