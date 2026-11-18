import 'package:flutter/material.dart';

/// Durée commune des apparitions / disparitions de pastilles et de blocs.
const _kRevealDuration = Duration(milliseconds: 180);

/// Apparition / disparition d'un enfant : sa taille (sur [axis], les deux si
/// `null`) et son opacité
/// passent de 0 à 1 quand [visible] devient vrai, et inversement.
///
/// Les voisins glissent avec la taille au lieu de sauter. Un enfant masqué n'est
/// plus dans l'arbre (rien à trouver, à toucher ni à lire pour l'accessibilité)
/// ; [onHidden] prévient quand la disparition est finie. Il est visible d'emblée
/// sauf si [appear] : alors il s'ouvre à la création (un élément ajouté en
/// cours de route, pas ceux présents à la première image). [initiallyOpen] fait
/// l'inverse pour un enfant déjà parti : il est d'abord pleinement ouvert, puis
/// se referme (la pastille d'un formulaire précédent).
class Reveal extends StatefulWidget {
  final bool visible;
  final Axis? axis;
  final bool appear;
  final bool initiallyOpen;
  final VoidCallback? onHidden;
  final Widget child;

  const Reveal({
    super.key,
    required this.visible,
    required this.child,
    this.axis = Axis.vertical,
    this.appear = false,
    this.initiallyOpen = false,
    this.onHidden,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kRevealDuration,
    value: widget.initiallyOpen || (widget.visible && !widget.appear) ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !widget.visible) {
        widget.onHidden?.call();
      }
    });
    if (widget.visible && widget.appear) {
      _controller.forward();
    } else if (!widget.visible && widget.initiallyOpen) {
      _controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // « Réduire les animations » : le changement est immédiat.
    _controller.duration = MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : _kRevealDuration;
  }

  @override
  void didUpdateWidget(Reveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (_controller.isDismissed && !widget.visible) {
          return const SizedBox.shrink();
        }
        // Un axe : seul celui-là se referme. `null` : les deux, pour qu'une
        // dernière pastille libère aussi sa hauteur (sans quoi la rangée vide
        // garderait sa hauteur puis la perdrait d'un coup). Un seul `Align`
        // pour les deux : deux `SizeTransition` imbriqués s'étaleraient en
        // largeur.
        final factor = _curve.value;
        final horizontal = widget.axis != Axis.vertical;
        final vertical = widget.axis != Axis.horizontal;
        return ClipRect(
          child: Align(
            alignment: vertical ? Alignment.topLeft : Alignment.centerLeft,
            widthFactor: horizontal ? factor : null,
            heightFactor: vertical ? factor : null,
            child: FadeTransition(opacity: _curve, child: child),
          ),
        );
      },
    );
  }
}

/// Une pastille de [AnimatedPillWrap] : sa clé identifie la pastille d'une
/// version de la liste à l'autre.
class PillEntry {
  final Key key;
  final Widget child;

  const PillEntry(this.key, this.child);
}

class _Slot {
  final Key key;
  Widget child;
  bool visible;
  final bool appear;

  /// Pastille d'un formulaire précédent : ouverte à la première image, puis
  /// elle se referme.
  bool startOpen = false;

  _Slot(this.key, this.child, {required this.visible, required this.appear});
}

/// Les pastilles affichées par le dernier [AnimatedPillWrap] qui s'y est
/// inscrit : le suivant les reprend pour animer le passage de l'une à l'autre.
class PillMemory {
  List<PillEntry> entries = const [];
}

/// `Wrap` de pastilles dont les ajouts et les retraits s'animent : la pastille
/// qui arrive s'ouvre (taille + fondu) et celle qui part se referme avant de
/// quitter l'arbre, pendant que les autres glissent pour combler.
///
/// Les pastilles présentes à la première image ne s'animent pas (ouvrir une
/// fiche ne doit rien faire bouger). Une pastille retirée garde sa place dans
/// l'ordre le temps de sa disparition et ne réagit plus au toucher.
class AnimatedPillWrap extends StatefulWidget {
  final List<PillEntry> entries;

  /// Écart horizontal entre pastilles (porté par chacune, pour qu'il se
  /// referme avec elle) et vertical entre les lignes.
  final double spacing;
  final double runSpacing;

  /// Où retrouver les pastilles du précédent et laisser les siennes. Avec
  /// [animateInitial], celles qui n'y étaient pas s'ouvrent dès la première
  /// image et celles qui n'ont plus lieu d'être se referment (au lieu de tout
  /// remplacer d'un coup).
  final PillMemory? memory;
  final bool animateInitial;

  const AnimatedPillWrap({
    super.key,
    required this.entries,
    this.spacing = 8,
    this.runSpacing = 8,
    this.memory,
    this.animateInitial = false,
  });

  @override
  State<AnimatedPillWrap> createState() => _AnimatedPillWrapState();
}

class _AnimatedPillWrapState extends State<AnimatedPillWrap> {
  late List<_Slot> _slots = _initialSlots();

  List<_Slot> _initialSlots() {
    if (!widget.animateInitial) {
      return [
        for (final e in widget.entries)
          _Slot(e.key, e.child, visible: true, appear: false),
      ];
    }
    final previous = [
      for (final e in widget.memory?.entries ?? const <PillEntry>[])
        _Slot(e.key, e.child, visible: true, appear: false),
    ];
    final slots = _merge(previous, widget.entries);
    for (final slot in slots) {
      if (!slot.visible) slot.startOpen = true;
    }
    return slots;
  }

  void _remember() {
    widget.memory?.entries = [
      for (final slot in _slots)
        if (slot.visible) PillEntry(slot.key, slot.child),
    ];
  }

  @override
  void initState() {
    super.initState();
    _remember();
  }

  @override
  void didUpdateWidget(AnimatedPillWrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _slots = _merge(_slots, widget.entries);
    _remember();
  }

  /// Nouvelle liste dans l'ordre demandé, plus les pastilles parties qui
  /// finissent de se refermer, à la place qu'elles occupaient.
  static List<_Slot> _merge(List<_Slot> current, List<PillEntry> entries) {
    final byKey = {for (final s in current) s.key: s};
    final incoming = {for (final e in entries) e.key};
    final result = <_Slot>[
      for (final e in entries)
        if (byKey[e.key] case final slot?)
          slot
            ..child = e.child
            ..visible = true
        else
          _Slot(e.key, e.child, visible: true, appear: true),
    ];
    for (var i = 0; i < current.length; i++) {
      final gone = current[i];
      if (incoming.contains(gone.key)) continue;
      gone.visible = false;
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final index = result.indexWhere((s) => s.key == current[j].key);
        if (index >= 0) {
          at = index + 1;
          break;
        }
      }
      result.insert(at, gone);
    }
    return result;
  }

  void _drop(Key key) {
    if (!mounted) return;
    setState(() => _slots.removeWhere((s) => s.key == key && !s.visible));
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: widget.runSpacing,
      children: [
        for (final slot in _slots)
          Reveal(
            // Enveloppée : la clé de la pastille reste unique pour qui la cherche.
            key: ValueKey(slot.key),
            axis: null,
            visible: slot.visible,
            appear: slot.appear,
            initiallyOpen: slot.startOpen,
            onHidden: () => _drop(slot.key),
            child: IgnorePointer(
              ignoring: !slot.visible,
              child: Padding(
                padding: EdgeInsets.only(right: widget.spacing),
                child: slot.child,
              ),
            ),
          ),
      ],
    );
  }
}
