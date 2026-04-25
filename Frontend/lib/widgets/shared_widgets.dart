// flutter-app/lib/widgets/shared_widgets.dart
// Redesigned: warmer palette, better reminder banner with snooze/dismiss,
// improved cards, responsive helpers

import 'package:flutter/material.dart';

class AlzColors {
  AlzColors._();
  static const navy     = Color(0xFF1A5276);
  static const ocean    = Color(0xFF2E86AB);
  static const warm     = Color(0xFFF5F0E8);
  static const amber    = Color(0xFFD68910);
  static const red      = Color(0xFFB03A2E);
  static const green    = Color(0xFF1D8348);
  static const textDark = Color(0xFF1A1A2E);
  static const grey     = Color(0xFFAAB7C4);
  static const softBlue = Color(0xFFD6EAF8);
  static const cardBg   = Color(0xFFFFFFFF);
  static const sage     = Color(0xFF7DCEA0);
  static const peach    = Color(0xFFF5CBA7);
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

bool isWideScreen(BuildContext ctx) => MediaQuery.of(ctx).size.width >= 900;
bool isTablet(BuildContext ctx) => MediaQuery.of(ctx).size.width >= 600;

// ── Sidebar nav item ───────────────────────────────────────────────────────────
class SideNavItem extends StatefulWidget {
  final IconData     icon;
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  final int?         badgeCount;

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
                ? Border.all(color: Colors.white.withOpacity(0.25), width: 1)
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
                    fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

// ── Card container ──────────────────────────────────────────────────────────────
class AlzCard extends StatelessWidget {
  final Widget    child;
  final EdgeInsets? padding;
  final Color?    borderColor;
  const AlzCard({super.key, required this.child, this.padding, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: padding ?? const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AlzColors.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: borderColor?.withOpacity(0.35) ?? Colors.black.withOpacity(0.07),
              width: borderColor != null ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: child,
      );
}

// ── Emotion chip ────────────────────────────────────────────────────────────────
class EmotionChip extends StatelessWidget {
  final String emotion;
  const EmotionChip(this.emotion, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = emotionColor(emotion);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(emotionIcon(emotion), size: 14, color: color),
        const SizedBox(width: 6),
        Text(emotion,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ── Status bubble ────────────────────────────────────────────────────────────────
class StatusBubble extends StatelessWidget {
  final String text;
  final Color  color;
  const StatusBubble({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 19, height: 1.55,
                fontWeight: FontWeight.w500, color: color.withOpacity(0.85))),
      );
}

// ── Empty state ──────────────────────────────────────────────────────────────────
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
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 40, color: Colors.black26),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black38)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black26, height: 1.5)),
          ]),
        ),
      );
}

// ── ReminderBanner — used in caregiver screen and as standalone widget ───────────
// (Patient screen uses its own inline reminder overlay for richer UX)
class ReminderBanner extends StatelessWidget {
  final String        task;
  final String?       reminderText;
  final String?       timeLabel;
  final int           attempts;
  final int           maxAttempts;
  final VoidCallback  onAcknowledge;
  final VoidCallback  onSnooze;
  final VoidCallback  onDismiss;

  const ReminderBanner({
    super.key,
    required this.task,
    required this.attempts,
    required this.maxAttempts,
    required this.onAcknowledge,
    required this.onSnooze,
    required this.onDismiss,
    this.reminderText,
    this.timeLabel,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.28),
                      blurRadius: 40, offset: const Offset(0, 16)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header gradient
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A5276), Color(0xFF2E86AB)],
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.alarm_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Time for a reminder',
                              style: TextStyle(color: Colors.white70, fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          if (timeLabel != null && timeLabel!.isNotEmpty)
                            Text(timeLabel!,
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        ]),
                      ),
                      // Progress dots
                      Row(children: List.generate(maxAttempts, (i) => Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < attempts
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                        ),
                      ))),
                    ]),
                    const SizedBox(height: 16),
                    Text("It's time to $task",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 22,
                            fontWeight: FontWeight.w800, height: 1.2)),
                    if (reminderText != null && reminderText!.isNotEmpty &&
                        reminderText != task) ...[
                      const SizedBox(height: 8),
                      Text(reminderText!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                    ],
                  ]),
                ),

                // Buttons
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(children: [
                    // Done button
                    _ReminderActionBtn(
                      onTap: onAcknowledge,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF1D8348), Color(0xFF27AE60)]),
                      shadowColor: const Color(0xFF1D8348),
                      icon: Icons.check_circle_rounded,
                      label: "Yes, I've done it!",
                      fontSize: 18,
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _OutlineBtn(
                          icon: Icons.snooze_rounded,
                          label: 'Snooze 10 min',
                          color: AlzColors.navy,
                          onTap: onSnooze)),
                      const SizedBox(width: 10),
                      Expanded(child: _OutlineBtn(
                          icon: Icons.notifications_off_rounded,
                          label: 'Dismiss',
                          color: AlzColors.grey,
                          onTap: onDismiss)),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      'You can also say "Yes, I\'ve done it" to the microphone',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black38, height: 1.4),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _ReminderActionBtn extends StatefulWidget {
  final VoidCallback onTap;
  final Gradient    gradient;
  final Color       shadowColor;
  final IconData    icon;
  final String      label;
  final double      fontSize;

  const _ReminderActionBtn({
    required this.onTap, required this.gradient, required this.shadowColor,
    required this.icon, required this.label, this.fontSize = 16,
  });

  @override
  State<_ReminderActionBtn> createState() => _ReminderActionBtnState();
}

class _ReminderActionBtnState extends State<_ReminderActionBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown:  (_) => setState(() => _pressed = true),
          onTapUp:    (_) { setState(() => _pressed = false); widget.onTap(); },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 17),
              decoration: BoxDecoration(
                gradient: widget.gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: widget.shadowColor.withOpacity(0.35),
                    blurRadius: 16, offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(widget.icon, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                Text(widget.label,
                    style: TextStyle(color: Colors.white,
                        fontSize: widget.fontSize, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      );
}

class _OutlineBtn extends StatefulWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _OutlineBtn({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  State<_OutlineBtn> createState() => _OutlineBtnState();
}

class _OutlineBtnState extends State<_OutlineBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter:  (_) => setState(() => _hovered = true),
        onExit:   (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: _hovered ? widget.color.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.color.withOpacity(0.35), width: 1.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.icon, color: widget.color, size: 20),
              const SizedBox(height: 4),
              Text(widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: widget.color, fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

// ── Web text field ──────────────────────────────────────────────────────────────
class AlzTextField extends StatelessWidget {
  final TextEditingController controller;
  final String  label;
  final IconData icon;
  final int     maxLines;
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
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AlzColors.navy, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}