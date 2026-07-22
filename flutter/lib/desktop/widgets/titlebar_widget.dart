import 'package:flutter/material.dart';

const sidebarColor = Color(0xFF7BB843);
const backgroundStartColor = Color(0xFF0A0C0A);
const backgroundEndColor = Color(0xFF101410);

class DesktopTitleBar extends StatelessWidget {
  final Widget? child;

  const DesktopTitleBar({Key? key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundStartColor, backgroundEndColor],
            stops: [0.0, 1.0]),
      ),
      child: Row(
        children: [
          Expanded(
            child: child ?? Offstage(),
          )
        ],
      ),
    );
  }
}