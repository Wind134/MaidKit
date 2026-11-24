import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class SheetScaffold extends StatefulWidget {
  final Widget? title;
  final String? titleText;
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;
  final double heightFactor;
  final double? height;
  final VoidCallback? onClose;
  final bool showHeader;

  const SheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.titleText,
    this.leading,
    this.actions = const [],
    this.heightFactor = 0.8,
    this.height,
    this.onClose,
    this.showHeader = true,
  });

  @override
  State<SheetScaffold> createState() => _SheetScaffoldState();
}

class _SheetScaffoldState extends State<SheetScaffold> {
  bool _isScrolled = false;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final isFloating = mediaQuery.size.width > 600;
    final bottomMargin = isFloating ? 24.0 : 0.0;
    final maxHeight =
        widget.height ?? mediaQuery.size.height * widget.heightFactor;
    final colorScheme = Theme.of(context).colorScheme;
    final radius = isFloating ? 20.0 : 24.0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        isFloating ? 24 : 0,
        isFloating ? 24 : 0,
        isFloating ? 24 : 0,
        keyboardInset + bottomMargin,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (maxHeight - keyboardInset - bottomMargin).clamp(
            0.0,
            maxHeight,
          ),
        ),
        child: Material(
          color: colorScheme.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          elevation: isFloating ? 6 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: isFloating
                ? BorderRadius.circular(radius)
                : BorderRadius.vertical(top: Radius.circular(radius)),
            side: isFloating
                ? BorderSide(color: colorScheme.outlineVariant)
                : BorderSide.none,
          ),
          child: Column(
            children: [
              if (widget.showHeader) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _isScrolled
                        ? colorScheme.surfaceContainerHigh
                        : Colors.transparent,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(radius),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 16,
                      left: 20,
                      right: 16,
                      bottom: 12,
                    ),
                    child: Row(
                      children: [
                        if (widget.leading != null) ...[
                          widget.leading!,
                          const SizedBox(width: 8),
                        ],
                        if (widget.title != null || widget.titleText != null)
                          Expanded(
                            child:
                                widget.title ??
                                Text(
                                  widget.titleText!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.5,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          )
                        else
                          const Spacer(),
                        ...widget.actions,
                        IconButton(
                          icon: Icon(
                            Symbols.close,
                            color: colorScheme.onSurface,
                          ),
                          onPressed: () => widget.onClose != null
                              ? widget.onClose?.call()
                              : Navigator.pop(context),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(36, 36),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    final isScrolled = notification.metrics.pixels > 0;
                    if (isScrolled != _isScrolled) {
                      setState(() {
                        _isScrolled = isScrolled;
                      });
                    }
                    return false;
                  },
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
