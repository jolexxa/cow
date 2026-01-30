// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:bloc/bloc.dart';
import 'package:blocterm/blocterm.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit([super.state = 0]);
}

class CloseTrackingCubit extends Cubit<int> {
  CloseTrackingCubit() : super(0);

  bool closed = false;

  @override
  Future<void> close() {
    closed = true;
    return super.close();
  }
}

class _ReadProvider extends StatelessComponent {
  const _ReadProvider({
    required this.listen,
  });

  final bool listen;

  @override
  Component build(BuildContext context) {
    final bloc = BlocProvider.of<CounterCubit>(context, listen: listen);
    return Text('count: ${bloc.state}');
  }
}

class _ReadValue extends StatelessComponent {
  const _ReadValue();

  @override
  Component build(BuildContext context) {
    return Text('value: ${Provider.of<int>(context)}');
  }
}

class _CreateSwitchRoot extends StatefulComponent {
  const _CreateSwitchRoot();

  @override
  State<_CreateSwitchRoot> createState() => _CreateSwitchRootState();
}

class _CreateSwitchRootState extends State<_CreateSwitchRoot> {
  late final CloseTrackingCubit Function(BuildContext) _createFirst;
  late final CloseTrackingCubit Function(BuildContext) _createSecond;
  CloseTrackingCubit? firstCreated;
  CloseTrackingCubit? secondCreated;
  bool _useFirst = true;

  @override
  void initState() {
    super.initState();
    _createFirst = (_) {
      final cubit = CloseTrackingCubit();
      firstCreated = cubit;
      return cubit;
    };
    _createSecond = (_) {
      final cubit = CloseTrackingCubit();
      secondCreated = cubit;
      return cubit;
    };
  }

  void switchToSecond() {
    setState(() {
      _useFirst = false;
    });
  }

  @override
  Component build(BuildContext context) {
    return BlocProvider<CloseTrackingCubit>.create(
      create: _useFirst ? _createFirst : _createSecond,
      child: Text('child'),
    );
  }
}

class _CreateToBlocRoot extends StatefulComponent {
  const _CreateToBlocRoot({
    required this.provided,
  });

  final CloseTrackingCubit provided;

  @override
  State<_CreateToBlocRoot> createState() => _CreateToBlocRootState();
}

class _CreateToBlocRootState extends State<_CreateToBlocRoot> {
  late final CloseTrackingCubit Function(BuildContext) _create;
  CloseTrackingCubit? created;
  bool _useCreate = true;

  @override
  void initState() {
    super.initState();
    _create = (_) {
      final cubit = CloseTrackingCubit();
      created = cubit;
      return cubit;
    };
  }

  void switchToProvided() {
    setState(() {
      _useCreate = false;
    });
  }

  @override
  Component build(BuildContext context) {
    if (_useCreate) {
      return BlocProvider<CloseTrackingCubit>.create(
        create: _create,
        child: Text('child'),
      );
    }
    return BlocProvider<CloseTrackingCubit>.value(
      value: component.provided,
      child: Text('child'),
    );
  }
}

void main() {
  test('BlocProvider', () async {
    await testNocterm('lookup with listen false', (tester) async {
      final cubit = CounterCubit(5);
      try {
        await tester.pumpComponent(
          BlocProvider<CounterCubit>.value(
            value: cubit,
            child: _ReadProvider(listen: false),
          ),
        );
        expect(tester.terminalState, containsText('count: 5'));
      } finally {
        await cubit.close();
      }
    });

    final missingTester = await NoctermTester.create();
    final previousHandler = NoctermError.onError;
    Object? capturedError;
    try {
      NoctermError.onError = (details) {
        capturedError = details.exception;
      };
      await missingTester.pumpComponent(_ReadProvider(listen: true));
      expect(capturedError, isA<BlocProviderNotFoundException>());
    } finally {
      NoctermError.onError = previousHandler;
      missingTester.dispose();
    }

    final error = BlocProviderNotFoundException(CounterCubit);
    expect(error.toString(), contains('BlocProvider<CounterCubit>'));
  });

  test('BlocProvider.create disposes bloc', () async {
    await testNocterm('closes bloc on unmount', (tester) async {
      late CloseTrackingCubit created;
      await tester.pumpComponent(
        BlocProvider<CloseTrackingCubit>.create(
          create: (_) => created = CloseTrackingCubit(),
          child: Text('child'),
        ),
      );

      expect(created.closed, isFalse);

      await tester.pumpComponent(Text('gone'));
      await tester.pump();

      expect(created.closed, isTrue);
    });
  });

  test('BlocProvider.create switches bloc when create changes', () async {
    await testNocterm('closes old bloc when create changes', (tester) async {
      await tester.pumpComponent(const _CreateSwitchRoot());

      final state = tester.findState<_CreateSwitchRootState>();
      final first = state.firstCreated;
      expect(first, isNotNull);
      expect(first!.closed, isFalse);

      state.switchToSecond();
      await tester.pump();
      await tester.pump();

      expect(first.closed, isTrue);
      expect(state.secondCreated, isNotNull);
      expect(state.secondCreated!.closed, isFalse);
    });
  });

  test('BlocProvider switches from create to bloc', () async {
    await testNocterm('closes owned bloc when switching to provided', (
      tester,
    ) async {
      final provided = CloseTrackingCubit();
      try {
        await tester.pumpComponent(
          _CreateToBlocRoot(provided: provided),
        );

        final state = tester.findState<_CreateToBlocRootState>();
        final created = state.created;
        expect(created, isNotNull);
        expect(created!.closed, isFalse);

        state.switchToProvided();
        await tester.pump();
        await tester.pump();

        expect(created.closed, isTrue);
        expect(provided.closed, isFalse);
      } finally {
        await provided.close();
      }
    });
  });

  test('BlocProvider ignores null bloc', () async {
    await testNocterm('renders child when bloc is null', (tester) async {
      await tester.pumpComponent(
        BlocProvider<CounterCubit>.value(
          value: null,
          child: Text('child'),
        ),
      );

      expect(tester.terminalState, containsText('child'));
    });
  });

  test('Provider', () async {
    await testNocterm('provides value to descendants', (tester) async {
      await tester.pumpComponent(
        Provider<int>(
          value: 3,
          child: const _ReadValue(),
        ),
      );

      expect(tester.terminalState, containsText('value: 3'));
    });

    await testNocterm('updateShouldNotify when value changes', (tester) async {
      const current = Provider<int>(value: 1, child: Text('child'));
      const same = Provider<int>(value: 1, child: Text('child'));
      const different = Provider<int>(value: 2, child: Text('child'));

      expect(current.updateShouldNotify(same), isFalse);
      expect(current.updateShouldNotify(different), isTrue);
    });
  });
}
