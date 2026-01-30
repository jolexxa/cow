// Ascii art :P
// ignore_for_file: unnecessary_raw_strings

import 'dart:async';

import 'package:nocterm/nocterm.dart';

/// Static cow face frames for sharing between widgets.
abstract final class CowIcons {
  static const List<String> idle0 = <String>[
    r'  )__(          ',
    r' ( oo )  __     ',
    r'  (__) \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_| *  ',
  ];

  static const List<String> idle1 = <String>[
    r'  )__(          ',
    r' ( oo )  __     ',
    r'  (__) \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_|*   ',
  ];

  static const List<String> idle2 = <String>[
    r'  )__(          ',
    r' ( oo )  __     ',
    r'  (__) \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_| *  ',
  ];

  static const List<String> idle3 = <String>[
    r'  )__(          ',
    r' ( oo )  __     ',
    r'  (__) \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_|  * ',
  ];

  static const List<String> idle4 = <String>[
    r'  )__(          ',
    r' ( oo )  __     ',
    r'  (__) \-- -\   ',
    r'    | ____ | \* ',
    r'    |_|  |_|    ',
  ];

  static const List<String> idle5 = <String>[
    r'  )__(          ',
    r' ( -- )  __     ',
    r'  (__) \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_| *  ',
  ];

  static const List<String> talk1 = <String>[
    r'  )__(          ',
    r' (oo  )  __     ',
    r' (__)  \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_| *  ',
  ];

  static const List<String> talk2 = <String>[
    r'  )__(          ',
    r' (oo  )  __     ',
    r' (*.)  \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_| *  ',
  ];

  static const List<String> talk3 = <String>[
    r'  )__(          ',
    r' (oo  )  __     ',
    r' (^ )  \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_| *  ',
  ];

  static const List<String> talk4 = <String>[
    r'  )__(          ',
    r' (oo  )  __     ',
    r' (.*)  \-- -\   ',
    r'    | ____ | |  ',
    r'    |_|  |_| *  ',
  ];

  static const List<List<String>> talkingFrames = <List<String>>[
    talk1,
    talk2,
    talk3,
    talk4,
  ];

  // Cute cow face cycling through "thinking" expressions
  static const List<List<String>> frames = <List<String>>[
    idle0,
    idle1,
    idle2,
    idle3,
    idle4,
    idle3,
    idle0,
    idle0,
    idle5,
    idle0,
  ];

  static const List<String> thoughtBubbles = <String>[
    r'     o ',
    r'   o   ',
    r'     o ',
    r'       ',
    r'       ',
  ];

  static const List<String> thoughtBubbles1 = <String>[
    r'       ',
    r'       ',
    r'     o ',
    r'       ',
    r'       ',
  ];

  static const List<String> thoughtBubbles2 = <String>[
    r'       ',
    r'   o   ',
    r'       ',
    r'       ',
    r'       ',
  ];

  static const List<String> thoughtBubbles3 = <String>[
    r'     o ',
    r'       ',
    r'       ',
    r'       ',
    r'       ',
  ];
  static const List<String> thoughtBubbles4 = <String>[
    r'    .  ',
    r'       ',
    r'       ',
    r'       ',
    r'       ',
  ];

  static const List<String> blank = <String>[
    r'       ',
    r'       ',
    r'       ',
    r'       ',
    r'       ',
  ];

  static const List<List<String>> thoughtFrames = <List<String>>[
    thoughtBubbles1,
    thoughtBubbles2,
    thoughtBubbles3,
    thoughtBubbles4,
    blank,
  ];

  static const List<String> speaking1 = <String>[
    r'       ',
    r'       ',
    r'      =',
    r'       ',
    r'       ',
  ];

  static const List<String> speaking2 = <String>[
    r'       ',
    r'    \  ',
    r'       ',
    r'    /  ',
    r'       ',
  ];

  static const List<String> speaking3 = <String>[
    r'       ',
    r'   .   ',
    r'       ',
    r'   .   ',
    r'       ',
  ];

  static const List<List<String>> speakingFrames = <List<String>>[
    speaking1,
    speaking2,
    speaking3,
    blank,
    blank,
  ];
}

/// A static cow face (not animated).
class CowIconStatic extends StatelessComponent {
  const CowIconStatic({super.key});

  @override
  Component build(BuildContext context) {
    return _AsciiFrame(
      frame: CowIcons.frames[0],
      padding: const EdgeInsets.only(top: 1, right: 1),
    );
  }
}

/// An animated ASCII cow face that cycles expressions while generating.
class CowIconAnimated extends StatelessComponent {
  const CowIconAnimated({super.key});

  @override
  Component build(BuildContext context) {
    return const _AnimatedAsciiFrames(
      frames: CowIcons.frames,
      interval: Duration(milliseconds: 400),
      padding: EdgeInsets.only(top: 1, right: 1),
    );
  }
}

/// An animated ASCII cow face that cycles expressions while generating.
class CowIconTalkingAnimated extends StatelessComponent {
  const CowIconTalkingAnimated({super.key});

  @override
  Component build(BuildContext context) {
    return const _AnimatedAsciiFrames(
      frames: CowIcons.talkingFrames,
      interval: Duration(milliseconds: 400),
      padding: EdgeInsets.only(top: 1, right: 1),
    );
  }
}

class _AsciiFrame extends StatelessComponent {
  const _AsciiFrame({required this.frame, required this.padding});

  final List<String> frame;
  final EdgeInsets padding;

  @override
  Component build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in frame)
            Text(line, style: const TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }
}

class _AnimatedAsciiFrames extends StatefulComponent {
  const _AnimatedAsciiFrames({
    required this.frames,
    required this.interval,
    required this.padding,
  });

  final List<List<String>> frames;
  final Duration interval;
  final EdgeInsets padding;

  @override
  State<_AnimatedAsciiFrames> createState() => _AnimatedAsciiFramesState();
}

class _AnimatedAsciiFramesState extends State<_AnimatedAsciiFrames> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(component.interval, (_) {
      if (!mounted) return;
      setState(() {
        final length = component.frames.length;
        _index = length == 0 ? 0 : (_index + 1) % length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final frames = component.frames;
    final frame = frames.isEmpty
        ? CowIcons.blank
        : frames[_index % frames.length];
    return _AsciiFrame(
      frame: frame,
      padding: component.padding,
    );
  }
}

/// A small trail of thought bubbles that lead into the cow.
class CowThoughtBubbles extends StatelessComponent {
  const CowThoughtBubbles({super.key});

  @override
  Component build(BuildContext context) {
    return const _AsciiFrame(
      frame: CowIcons.thoughtBubbles,
      padding: EdgeInsets.only(right: 1),
    );
  }
}

/// Animated thought bubbles to show "thinking" while generating.
class CowThoughtBubblesAnimated extends StatelessComponent {
  const CowThoughtBubblesAnimated({super.key});

  @override
  Component build(BuildContext context) {
    return const _AnimatedAsciiFrames(
      frames: CowIcons.thoughtFrames,
      interval: Duration(milliseconds: 300),
      padding: EdgeInsets.only(right: 1),
    );
  }
}

/// Animated "speaking" bubbles for the response phase.
class CowSpeakingBubblesAnimated extends StatelessComponent {
  const CowSpeakingBubblesAnimated({super.key});

  @override
  Component build(BuildContext context) {
    return const _AnimatedAsciiFrames(
      frames: CowIcons.speakingFrames,
      interval: Duration(milliseconds: 220),
      padding: EdgeInsets.only(top: 1, right: 1),
    );
  }
}
