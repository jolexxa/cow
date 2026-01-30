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

class _SwitchingRoot extends StatefulComponent {
  const _SwitchingRoot({
    required this.first,
    required this.second,
  });

  final CounterCubit first;
  final CounterCubit second;

  @override
  State<_SwitchingRoot> createState() => _SwitchingRootState();
}

class _SwitchingRootState extends State<_SwitchingRoot> {
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
    return BlocBuilder<CounterCubit, int>(
      bloc: _current,
      builder: (context, state) => Text('count: $state'),
    );
  }
}

class _ProviderSwitchRoot extends StatefulComponent {
  const _ProviderSwitchRoot({
    required this.first,
    required this.second,
  });

  final CounterCubit first;
  final CounterCubit second;

  @override
  State<_ProviderSwitchRoot> createState() => _ProviderSwitchRootState();
}

class _ProviderSwitchRootState extends State<_ProviderSwitchRoot> {
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
      child: BlocBuilder<CounterCubit, int>(
        builder: (context, state) => Text('count: $state'),
      ),
    );
  }
}

class _ExplicitToggleRoot extends StatefulComponent {
  const _ExplicitToggleRoot({
    required this.explicit,
    required this.provided,
  });

  final CounterCubit explicit;
  final CounterCubit provided;

  @override
  State<_ExplicitToggleRoot> createState() => _ExplicitToggleRootState();
}

class _ExplicitToggleRootState extends State<_ExplicitToggleRoot> {
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
      child: BlocBuilder<CounterCubit, int>(
        bloc: _useExplicit ? component.explicit : null,
        builder: (context, state) => Text('count: $state'),
      ),
    );
  }
}

void main() {
  test('BlocBuilder', () async {
    await testNocterm('renders initial bloc state', (tester) async {
      final cubit = CounterCubit();
      try {
        await tester.pumpComponent(
          BlocBuilder<CounterCubit, int>(
            bloc: cubit,
            builder: (context, state) => Text('count: $state'),
          ),
        );

        expect(tester.terminalState, containsText('count: 0'));
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('rebuilds when the bloc emits', (tester) async {
      final cubit = CounterCubit();
      try {
        await tester.pumpComponent(
          BlocBuilder<CounterCubit, int>(
            bloc: cubit,
            builder: (context, state) => Text('count: $state'),
          ),
        );

        cubit.emit(1);
        await tester.pump();
        await tester.pump();

        expect(tester.terminalState, containsText('count: 1'));
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('buildWhen controls rebuilds', (tester) async {
      final cubit = CounterCubit();
      try {
        await tester.pumpComponent(
          BlocBuilder<CounterCubit, int>(
            bloc: cubit,
            buildWhen: (previous, current) => current.isEven,
            builder: (context, state) => Text('count: $state'),
          ),
        );

        cubit.emit(1);
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 0'));

        cubit.emit(2);
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 2'));
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('uses BlocProvider when bloc is not provided', (
      tester,
    ) async {
      final cubit = CounterCubit();
      try {
        await tester.pumpComponent(
          BlocProvider<CounterCubit>.value(
            value: cubit,
            child: BlocBuilder<CounterCubit, int>(
              builder: (context, state) => Text('count: $state'),
            ),
          ),
        );

        expect(tester.terminalState, containsText('count: 0'));
      } finally {
        await cubit.close();
      }
    });

    await testNocterm('switches blocs when bloc property changes', (
      tester,
    ) async {
      final first = CounterCubit();
      final second = CounterCubit(10);
      try {
        await tester.pumpComponent(
          _SwitchingRoot(first: first, second: second),
        );
        expect(tester.terminalState, containsText('count: 0'));

        tester.findState<_SwitchingRootState>().switchToSecond();
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 10'));

        second.emit(11);
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 11'));
      } finally {
        await first.close();
        await second.close();
      }
    });

    await testNocterm('responds when provider bloc changes', (tester) async {
      final first = CounterCubit();
      final second = CounterCubit(10);
      try {
        await tester.pumpComponent(
          _ProviderSwitchRoot(first: first, second: second),
        );
        expect(tester.terminalState, containsText('count: 0'));

        final _ = tester.findState<_ProviderSwitchRootState>()
          ..switchToSecond();
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 10'));
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
      try {
        await tester.pumpComponent(
          _ExplicitToggleRoot(explicit: explicit, provided: provided),
        );
        expect(tester.terminalState, containsText('count: 1'));

        final _ = tester.findState<_ExplicitToggleRootState>()..dropExplicit();
        await tester.pump();
        await tester.pump();
        expect(tester.terminalState, containsText('count: 2'));
      } finally {
        await explicit.close();
        await provided.close();
      }
    });

    await testNocterm('ignores emits after unmount', (tester) async {
      final bloc = LeakyBloc();
      await tester.pumpComponent(
        BlocBuilder<LeakyBloc, int>(
          bloc: bloc,
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
