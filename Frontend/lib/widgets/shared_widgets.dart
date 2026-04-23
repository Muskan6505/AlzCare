// flutter-app/lib/widgets/shared_widgets.dart
// Web-optimised shared widgets.
// Key web additions:
//   • WebLayout — responsive sidebar for wide screens (desktop/tablet)
//   • Hover effects via MouseRegion
//   • Larger click targets and proper cursor styles

import 'package:flutter/material.dart';

class AlzColors {
  AlzColors._();
  static const navy     = Color(0xFF1A5276);
  static const ocean    = Color(0xFF2E86AB);
  static const warm     = Color(0xFFF7F3EE);
  static const amber    = Color(0xFFD68910);
  static const red      = Color(0xFFB03A2E);
  static const green    = Color(0xFF1D8348);
  static const textDark = Color(0xFF1A1A2E);
  static const grey     = Color(0xFFAAB7C4);
  static const softBlue = Color(0xFFD6EAF8);
  static const cardBg   = Color(0xFFFFFFFF);
}

Color emotionColor(String emotion) {
  switch (emotion) {
    case 'Agitated': return AlzColors.red;
    case 'Fear':     return AlzColors.red;
    case 'Sad':      return AlzColors.amber;
    case 'Happy':    return AlzColors.green;
    default:         return AlzColors.navy;
  }
}

IconData emotionIcon(String emotion) {
  switch (emotion) {
    case 'Agitated': return Icons.warning_rounded;
    case 'Fear':     return Icons.sentiment_very_dissatisfied;
    case 'Sad':      return Icons.sentiment_dissatisfied;
    case 'Happy':    return Icons.sentiment_very_satisfied;
    default:         return Icons.sentiment_neutral;
  }
}

// ── Responsive breakpoints ─────────────────────────────────────────────────────
bool isWideScreen(BuildContext ctx) => MediaQuery.of(ctx).size.width >= 900;
bool isTablet(BuildContext ctx) => MediaQuery.of(ctx).size.width >= 600;

// ── Web-style sidebar nav item ─────────────────────────────────────────────────
class SideNavItem extends StatefulWidget {
  final IconData icon;
  final String   label;
  final bool     selected;
  final VoidCallback onTap;
  final int?     badgeCount;

  const SideNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount,
  });

  @override
  State<SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<SideNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter:  (_) => setState(() => _hovered = true),
      onExit:   (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? Colors.white.withOpacity(0.18)
                : _hovered
                    ? Colors.white.withOpacity(0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: widget.selected
                ? Border.all(color: Colors.white.withOpacity(0.3), width: 1)
                : null,
          ),
          child: Row(children: [
            Stack(children: [
              Icon(widget.icon,
                  color: widget.selected ? Colors.white : Colors.white60,
                  size: 22),
              if (widget.badgeCount != null && widget.badgeCount! > 0)
                Positioned(
                  top: -2, right: -4,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                        color: AlzColors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${widget.badgeCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Text(widget.label,
                style: TextStyle(
                    color: widget.selected ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

// ── Web card container ─────────────────────────────────────────────────────────
class AlzCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;
  const AlzCard({super.key, required this.child, this.padding, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: padding ?? const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AlzColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: borderColor?.withOpacity(0.35) ??
                  Colors.black.withOpacity(0.07),
              width: borderColor != null ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );
}

// ── Emotion chip ──────────────────────────────────────────────────────────────
class EmotionChip extends StatelessWidget {
  final String emotion;
  const EmotionChip(this.emotion, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = emotionColor(emotion);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(emotionIcon(emotion), size: 14, color: color),
        const SizedBox(width: 5),
        Text(emotion,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ── Status bubble ──────────────────────────────────────────────────────────────
class StatusBubble extends StatelessWidget {
  final String text;
  final Color  color;
  const StatusBubble({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20, height: 1.45,
                fontWeight: FontWeight.w500, color: color)),
      );
}

// ── Empty state ────────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 72, color: Colors.black12),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black38)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black26)),
          ]),
        ),
      );
}

// ── Persistent Nagger banner ───────────────────────────────────────────────────
class ReminderBanner extends StatelessWidget {
  final String       task;
  final int          attempts;
  final int          maxAttempts;
  final VoidCallback onAcknowledge;
  final VoidCallback onDismiss;
  const ReminderBanner({
    super.key, required this.task, required this.attempts,
    required this.maxAttempts, required this.onAcknowledge, required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AlzColors.navy,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.alarm, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Reminder ($attempts/$maxAttempts)',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onDismiss,
                      child: const Icon(Icons.close, color: Colors.white54, size: 22),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text("It's time to $task",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 22),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onAcknowledge,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline,
                              color: AlzColors.navy, size: 24),
                          SizedBox(width: 10),
                          Text("Yes, I've done it!",
                              style: TextStyle(
                                  color: AlzColors.navy,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

// ── Web text field ─────────────────────────────────────────────────────────────
class AlzTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final String? hint;
  const AlzTextField(this.controller, this.label, this.icon,
      {super.key, this.maxLines = 1, this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          hintText:  hint,
          labelStyle: const TextStyle(fontSize: 15),
          prefixIcon: Icon(icon, size: 20),
          border:         OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder:  OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AlzColors.navy, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
