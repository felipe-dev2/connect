import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';

class Button extends StatefulWidget {
  final GestureTapCallback onTap;
  final String text;
  final double? textSize;
  final double? minWidth;
  final bool isOutline;
  final double? padding;
  final Color? textColor;
  final double? radius;
  final Color? borderColor;

  Button({
    Key? key,
    this.minWidth,
    this.isOutline = false,
    this.textSize,
    this.padding,
    this.textColor,
    this.radius,
    this.borderColor,
    required this.onTap,
    required this.text,
  }) : super(key: key);

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  RxBool hover = false.obs;
  RxBool pressed = false.obs;

  @override
  Widget build(BuildContext context) {
    return Obx(() => InkWell(
          onTapDown: (_) => pressed.value = true,
          onTapUp: (_) => pressed.value = false,
          onTapCancel: () => pressed.value = false,
          onHover: (value) => hover.value = value,
          onTap: widget.onTap,
          child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.minWidth ?? 70.0,
              ),
              child: Container(
                padding: EdgeInsets.all(widget.padding ?? 4.5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.isOutline
                      ? (hover.value
                          ? MyTheme.greenDark.withOpacity(0.25)
                          : Colors.transparent)
                      : (pressed.value
                          ? MyTheme.greenDark
                          : (hover.value
                              ? MyTheme.greenBright
                              : MyTheme.green)),
                  border: Border.all(
                    color: widget.isOutline
                        ? (hover.value
                            ? MyTheme.green
                            : widget.borderColor ?? MyTheme.hairline)
                        : (hover.value
                            ? MyTheme.greenBright
                            : MyTheme.green),
                  ),
                  borderRadius:
                      BorderRadius.circular(widget.radius ?? MyTheme.radiusSm),
                ),
                child: Text(
                  translate(
                    widget.text,
                  ),
                  style: TextStyle(
                      fontSize: widget.textSize ?? 12.0,
                      fontWeight: FontWeight.w600,
                      color: widget.isOutline
                          ? widget.textColor ?? MyTheme.textPrimary
                          : const Color(0xFF0A0C0A)),
                ).marginSymmetric(horizontal: 12),
              )),
        ));
  }
}

class FixedWidthButton extends StatefulWidget {
  final GestureTapCallback onTap;
  final String text;
  final double? textSize;
  final double width;
  final bool isOutline;
  final double? padding;
  final Color? textColor;
  final double? radius;
  final Color? borderColor;
  final int? maxLines;

  FixedWidthButton({
    Key? key,
    required this.width,
    this.maxLines,
    this.isOutline = false,
    this.textSize,
    this.padding,
    this.textColor,
    this.radius,
    this.borderColor,
    required this.onTap,
    required this.text,
  }) : super(key: key);

  @override
  State<FixedWidthButton> createState() => _FixedWidthButtonState();
}

class _FixedWidthButtonState extends State<FixedWidthButton> {
  RxBool hover = false.obs;
  RxBool pressed = false.obs;

  @override
  Widget build(BuildContext context) {
    return Obx(() => InkWell(
          onTapDown: (_) => pressed.value = true,
          onTapUp: (_) => pressed.value = false,
          onTapCancel: () => pressed.value = false,
          onHover: (value) => hover.value = value,
          onTap: widget.onTap,
          child: Container(
            width: widget.width,
            padding: EdgeInsets.all(widget.padding ?? 4.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.isOutline
                  ? (hover.value
                      ? MyTheme.greenDark.withOpacity(0.25)
                      : Colors.transparent)
                  : (pressed.value
                      ? MyTheme.greenDark
                      : (hover.value ? MyTheme.greenBright : MyTheme.green)),
              border: Border.all(
                color: widget.isOutline
                    ? (hover.value
                        ? MyTheme.green
                        : widget.borderColor ?? MyTheme.hairline)
                    : (hover.value ? MyTheme.greenBright : MyTheme.green),
              ),
              borderRadius:
                  BorderRadius.circular(widget.radius ?? MyTheme.radiusSm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: AutoSizeText(
                    translate(
                      widget.text,
                    ),
                    maxLines: widget.maxLines ?? 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: widget.textSize ?? 12.0,
                        fontWeight: FontWeight.w600,
                        color: widget.isOutline
                            ? widget.textColor ?? MyTheme.textPrimary
                            : const Color(0xFF0A0C0A)),
                  ).marginSymmetric(horizontal: 12),
                ),
              ],
            ),
          ),
        ));
  }
}
