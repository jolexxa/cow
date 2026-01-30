// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:bloc/bloc.dart';
import 'package:blocterm/blocterm.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import 'leaky_bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit([super.state = 0]);
}

class _SwitchingConsumerRoot extends StatefulComponent {
  const _SwitchingConsumerRoot({
    required this.first,
    required this.second,
    required this.onListen,
  });

  final CounterCubit first;
  final CounterCubit second;
  final void Function(int value) onListen;

  @override
  State<_SwitchingConsumerRoot> createState() => _SwitchingConsumerRootState();
}

class _SwitchingConsumerRootState extends State<_SwitchingConsumerRoot> {
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
    return BlocConsumer<CounterCubit, int>(
      bloc: _current,
      listener: (_, value) => component.onListen(value),
      builder: (_, state) => Text('count: $state'),
    );
  }
}

class _ProviderSwitchConsumerRoot extends StatefulComponent {
  const _ProviderSwitchConsumerRoot({
    required this.first,
    required this.second,
    required this.onListen,
  });

  final CounterCubit first;
  final CounterCubit second;
  final void Function(int value) onListen;

  @override
  State<_ProviderSwitchConsumerRoot> createState() =>
      _ProviderSwitchConsumerRootState();
}

class _ProviderSwitchConsumerRootState
    extends State<_ProviderSwitchConsumerRoot> {
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
      child: BlocConsumer<CounterCubit, int>(
        listener: (_, value) => component.onListen(value),
        builder: (_, state) => Text('count: $state'),
      ),
    );
  }
}

class _ExplicitToggleConsumerRoot extends StatefulComponent {
  const _ExplicitToggleConsumerRoot({
    required this.explicit,
    required this.provided,
    required this.onListen,
  });

  final CounterCubit explicit;
  final CounterCubit provided;
  final void Function(int value) onListen;

  @override
  State<_ExplicitToggleConsumerRoot> createState() =>
      _ExplicitToggleConsumerRootState();
}

class _ExplicitToggleConsumerRootState
    extends State<_ExplicitToggleConsumerRoot> {
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
      child: BlocConsumer<CounterCubit, int>(
        bloc: _useExplicit ? component.explicit : null,
        listener: (_, value) => component.onListen(value),
        builder: (_, state) => Text('count: $state'),
      ),
    );
  }
}

void main() {
  test('BlocConsumer', () async {
    await testNocterm('rebuilds and listens on state changes', (tester) async {
      final cubit = CounterCubit();
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          BlocConsumer<CounterCubit, int>(
            bloc: cubit,
            listener: (_, value) => seen.add(value),
            builder: (context, state) => Text('count: $state'),
          ),
        );
        expect(tester.terminalState, containsText('count: 0'));

        cubit.emit(1);
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 1'));
        expect(seen, [1]);
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('buildWhen and listenWhen are respected', (tester) async {
      final cubit = CounterCubit();
      final seen = <int>[];
      try {
        await tester.pumpComponent(
          BlocConsumer<CounterCubit, int>(
            bloc: cubit,
            buildWhen: (previous, current) => current.isEven,
            listenWhen: (previous, current) => current.isOdd,
            listener: (_, value) => seen.add(value),
            builder: (context, state) => Text('count: $state'),
          ),
        );

        cubit.emit(1);
        await tester.pump();
        await tester.pump();
        expect(seen, [1]);
        expect(tester.terminalState, containsText('count: 0'));

        cubit.emit(2);
        await tester.pump();
        await tester.pump();
        expect(seen, [1]);
        expect(tester.terminalState, containsText('count: 2'));
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
            child: BlocConsumer<CounterCubit, int>(
              listener: (_, value) => seen.add(value),
              builder: (context, state) => Text('count: $state'),
            ),
          ),
        );

        cubit.emit(3);
        await tester.pump();
        await tester.pump();
        expect(seen, [3]);
        expect(tester.terminalState, containsText('count: 3'));
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
          _SwitchingConsumerRoot(
            first: first,
            second: second,
            onListen: seen.add,
          ),
        );
        expect(tester.terminalState, containsText('count: 0'));

        tester.findState<_SwitchingConsumerRootState>().switchToSecond();
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 10'));

        second.emit(11);
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 11'));
        expect(seen, [11]);
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
          _ProviderSwitchConsumerRoot(
            first: first,
            second: second,
            onListen: seen.add,
          ),
        );
        expect(tester.terminalState, containsText('count: 0'));

        tester.findState<_ProviderSwitchConsumerRootState>().switchToSecond();
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 10'));

        second.emit(11);
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 11'));
        expect(seen, [11]);
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
          _ExplicitToggleConsumerRoot(
            explicit: explicit,
            provided: provided,
            onListen: seen.add,
          ),
        );
        expect(tester.terminalState, containsText('count: 1'));

        tester.findState<_ExplicitToggleConsumerRootState>().dropExplicit();
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 2'));

        provided.emit(3);
        await tester.pump();
        await tester.pump();
        expect(seen, [3]);
      } finally {
        await explicit.close();
        await provided.close();
      }
    });

    await testNocterm('ignores emits after unmount', (tester) async {
      final bloc = LeakyBloc();
      await tester.pumpComponent(
        BlocConsumer<LeakyBloc, int>(
          bloc: bloc,
          listener: (_, _) {},
          builder: (context, state) => Text('count: $state'),
        ),
      );

      await tester.pumpComponent(Text('gone'));
      await tester.pump();

      bloc.emit(1);
      await tester.pump();
    });
  });
}
