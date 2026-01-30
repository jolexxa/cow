// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:bloc/bloc.dart';
import 'package:blocterm/blocterm.dart';
import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:test/test.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit([super.state = 0]);
}

class _SwitchingListenerRoot extends StatefulComponent {
  const _SwitchingListenerRoot({
    required this.first,
    required this.second,
    required this.onListen,
  });

  final CounterCubit first;
  final CounterCubit second;
  final void Function(int value) onListen;

  @override
  State<_SwitchingListenerRoot> createState() => _SwitchingListenerRootState();
}

class _SwitchingListenerRootState extends State<_SwitchingListenerRoot> {
  late CounterCubit _current;

  @override
  void initState() {
    super.initState();
    _current = component.first;
  }

  void switchToSecond() {
    setState(() {
      _current = component.second;
    });
  }

  @override
  Component build(BuildContext context) {
    return BlocListener<CounterCubit, int>(
      bloc: _current,
      listener: (_, value) => component.onListen(value),
      child: Text('listener'),
    );
  }
}

class _ProviderSwitchListenerRoot extends StatefulComponent {
  const _ProviderSwitchListenerRoot({
    required this.first,
    required this.second,
    required this.onListen,
  });

  final CounterCubit first;
  final CounterCubit second;
  final void Function(int value) onListen;

  @override
  State<_ProviderSwitchListenerRoot> createState() =>
      _ProviderSwitchListenerRootState();
}

class _ProviderSwitchListenerRootState
    extends State<_ProviderSwitchListenerRoot> {
  late CounterCubit _current;

  @override
  void initState() {
    super.initState();
    _current = component.first;
  }

  void switchToSecond() {
    setState(() {
      _current = component.second;
    });
  }

  @override
  Component build(BuildContext context) {
    return BlocProvider<CounterCubit>.value(
      value: _current,
      child: BlocListener<CounterCubit, int>(
        listener: (_, value) => component.onListen(value),
        child: Text('listener'),
      ),
    );
  }
}

class _ExplicitToggleListenerRoot extends StatefulComponent {
  const _ExplicitToggleListenerRoot({
    required this.explicit,
    required this.provided,
    required this.onListen,
  });

  final CounterCubit explicit;
  final CounterCubit provided;
  final void Function(int value) onListen;

  @override
  State<_ExplicitToggleListenerRoot> createState() =>
      _ExplicitToggleListenerRootState();
}

class _ExplicitToggleListenerRootState
    extends State<_ExplicitToggleListenerRoot> {
  bool _useExplicit = true;

  void dropExplicit() {
    setState(() {
      _useExplicit = false;
    });
  }

  @override
  Component build(BuildContext context) {
    return BlocProvider<CounterCubit>.value(
      value: component.provided,
      child: BlocListener<CounterCubit, int>(
        bloc: _useExplicit ? component.explicit : null,
        listener: (_, value) => component.onListen(value),
        child: Text('listener'),
      ),
    );
  }
}

void main() {
  test('BlocListener', () async {
    await testNocterm('invokes listener on state changes', (tester) async {
      final cubit = CounterCubit();
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          BlocListener<CounterCubit, int>(
            bloc: cubit,
            listener: (_, value) => seen.add(value),
            child: Text('listener'),
          ),
        );

        cubit.emit(1);
        await tester.pump();
        await tester.pump();
        expect(seen, [1]);

        cubit.emit(2);
        await tester.pump();
        await tester.pump();
        expect(seen, [1, 2]);
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('listenWhen controls notifications', (tester) async {
      final cubit = CounterCubit();
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          BlocListener<CounterCubit, int>(
            bloc: cubit,
            listenWhen: (previous, current) => current.isEven,
            listener: (_, value) => seen.add(value),
            child: Text('listener'),
          ),
        );

        cubit.emit(1);
        await tester.pump();
        await tester.pump();
        expect(seen, isEmpty);

        cubit.emit(2);
        await tester.pump();
        await tester.pump();
        expect(seen, [2]);
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('uses BlocProvider when bloc is not provided', (
      tester,
    ) async {
      final cubit = CounterCubit();
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          BlocProvider<CounterCubit>.value(
            value: cubit,
            child: BlocListener<CounterCubit, int>(
              listener: (_, value) => seen.add(value),
              child: Text('listener'),
            ),
          ),
        );

        cubit.emit(3);
        await tester.pump();
        await tester.pump();
        expect(seen, [3]);
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('switches blocs when bloc property changes', (
      tester,
    ) async {
      final first = CounterCubit();
      final second = CounterCubit(10);
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          _SwitchingListenerRoot(
            first: first,
            second: second,
            onListen: seen.add,
          ),
        );

        first.emit(1);
        await tester.pump();
        await tester.pump();
        expect(seen, [1]);

        tester.findState<_SwitchingListenerRootState>().switchToSecond();
        await tester.pump();
        await tester.pump();

        second.emit(11);
        await tester.pump();
        await tester.pump();
        expect(seen, [1, 11]);
      } finally {
        await first.close();
        await second.close();
      }
    });

    await testNocterm('responds when provider bloc changes', (tester) async {
      final first = CounterCubit();
      final second = CounterCubit(10);
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          _ProviderSwitchListenerRoot(
            first: first,
            second: second,
            onListen: seen.add,
          ),
        );

        first.emit(1);
        await tester.pump();
        await tester.pump();
        expect(seen, [1]);

        tester.findState<_ProviderSwitchListenerRootState>().switchToSecond();
        await tester.pump();
        await tester.pump();

        second.emit(11);
        await tester.pump();
        await tester.pump();
        expect(seen, [1, 11]);
      } finally {
        await first.close();
        await second.close();
      }
    });

    await testNocterm('falls back to provider when explicit bloc removed', (
      tester,
    ) async {
      final explicit = CounterCubit(1);
      final provided = CounterCubit(2);
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          _ExplicitToggleListenerRoot(
            explicit: explicit,
            provided: provided,
            onListen: seen.add,
          ),
        );

        explicit.emit(3);
        await tester.pump();
        await tester.pump();
        expect(seen, [3]);

        tester.findState<_ExplicitToggleListenerRootState>().dropExplicit();
        await tester.pump();
        await tester.pump();

        provided.emit(4);
        await tester.pump();
        await tester.pump();
        expect(seen, [3, 4]);
      } finally {
        await explicit.close();
        await provided.close();
      }
    });

    await testNocterm('stops listening after unmount', (tester) async {
      final cubit = CounterCubit();
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          BlocListener<CounterCubit, int>(
            bloc: cubit,
            listener: (_, value) => seen.add(value),
            child: Text('listener'),
          ),
        );

        await tester.pumpComponent(Text('gone'));
        await tester.pump();

        cubit.emit(1);
        await tester.pump();
        await tester.pump();
        expect(seen, isEmpty);
      } finally {
        await cubit.close();
      }
    });
  });
}
