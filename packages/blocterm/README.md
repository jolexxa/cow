# 🖥️ Blocterm

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link] [![Coverage][coverage_badge]][coverage_link] [![License: MIT][license_badge]][license_link]

Use [bloc] to build beautiful terminal experiences with [Nocterm].

## Usage ✨

```dart
import 'package:bloc/bloc.dart';
import 'package:blocterm/blocterm.dart';
import 'package:nocterm/nocterm.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void inc() => emit(state + 1);
}

class CounterView extends StatelessComponent {
  const CounterView({super.key});

  @override
  Component build(BuildContext context) {
    return BlocProvider.value(
      value: CounterCubit(),
      child: BlocBuilder<CounterCubit, int>(
        builder: (context, state) {
          return Text('count: $state');
        },
      ),
    );
  }
}
```

## Installation 💻

**❗ In order to start using Blocterm you must have the [Dart SDK][dart_install_link] installed on your machine.**

Install via `dart pub add`:

```sh
dart pub add blocterm
```

[dart_install_link]: https://dart.dev/get-dart
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[coverage_badge]: coverage_badge.svg
[coverage_link]: coverage/lcov.info
[bloc]: https://pub.dev/packages/bloc
[Nocterm]: https://pub.dev/packages/nocterm
