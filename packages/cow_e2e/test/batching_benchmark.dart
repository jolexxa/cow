// Batching benchmark: runs sequential vs concurrent throughput N times,
// discards the first (warmup) run, and reports averages.
//
// Usage:
//   cd packages/cow_e2e
//   dart test test/batching_benchmark.dart -r expanded

@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:cow_brain/cow_brain.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _runs = 10;
// Short prompts — decode-heavy benchmark (tiny prefill).
const _shortPrompts = [
  'What is 2+2? Answer in one word.',
  'Name three colors. Be brief.',
  'What is the capital of France? One word.',
];

// Long prompts — prefill-heavy benchmark
// Batching benefits show up primarily during prefill on Apple Silicon.
const _longPrompts = [
  '''You are a world-class software architect reviewing a complex distributed system. The system consists of multiple microservices communicating over gRPC, with a shared PostgreSQL database for persistent storage and Redis for caching. The frontend is a React application that communicates with a BFF (Backend for Frontend) layer written in Go. The authentication service uses JWT tokens with refresh token rotation, and there is a rate limiting service implemented using a token bucket algorithm. The deployment is managed through Kubernetes with Helm charts, and the CI/CD pipeline uses GitHub Actions with ArgoCD for GitOps-based deployments. The monitoring stack includes Prometheus for metrics, Grafana for dashboards, Jaeger for distributed tracing, and the ELK stack for centralized logging. Recently, the team has been experiencing issues with cascading failures when the database connection pool is exhausted, leading to timeout errors across multiple services. The circuit breaker pattern has been implemented using Hystrix, but it doesn't seem to be triggering correctly. Additionally, there are concerns about data consistency in the event-driven architecture where some services use eventual consistency patterns with Kafka as the message broker. The team is also considering migrating from a monolithic database to a CQRS pattern with event sourcing for the order management domain. Given all of this context, analyze the cascading failure scenario and propose a comprehensive solution that addresses the root cause while maintaining system reliability. Be thorough and specific.''',
  '''You are an expert in programming language theory and compiler design. Consider the following scenario: we are designing a new programming language that combines the best features of Rust's ownership system, Haskell's type system, and Python's ergonomics. The language should support algebraic data types with pattern matching, linear types for resource management, effect handlers for managing side effects, and a powerful macro system similar to Rust's procedural macros. The type inference engine should be based on bidirectional type checking with support for higher-ranked polymorphism and type-level computation. The compiler architecture should include a front-end that produces a typed AST, a middle-end that performs optimizations on a continuation-passing style intermediate representation, and a back-end that targets both LLVM IR and WebAssembly. The garbage collector should use a generational approach with region-based memory management for stack-allocated data. The standard library should include support for async/await with structured concurrency, algebraic effects, and a comprehensive collections library with persistent data structures. The build system should support incremental compilation with fine-grained dependency tracking at the function level. Given these requirements, design the core type system, explain how ownership and borrowing would interact with algebraic effects, and outline the compilation pipeline from source code to optimized machine code. Be precise about the formal semantics where possible.''',
  '''You are a senior data scientist working on a large-scale recommendation system for an e-commerce platform with 50 million active users and 10 million products. The current system uses a two-tower neural network architecture for candidate generation, followed by a ranking model that uses a wide-and-deep architecture combining handcrafted features with learned embeddings. The feature store is built on Apache Feast and serves both batch and real-time features. The training pipeline uses Apache Spark for data preprocessing, followed by distributed training on a GPU cluster using PyTorch with DeepSpeed for model parallelism. The serving infrastructure uses TensorFlow Serving behind an Envoy proxy with A/B testing capabilities managed through a feature flagging system. The evaluation framework tracks multiple metrics including NDCG, MAP, coverage, novelty, and business metrics like revenue per session and conversion rate. Recent experiments have shown that incorporating user session context through a transformer-based sequence model improves click-through rate by 3.2%, but the latency budget of 50ms p99 makes it challenging to serve the full model in production. The team is exploring several approaches including model distillation, quantization, and caching strategies. Additionally, there are fairness concerns as the model shows disparate impact across different user demographics, and the team needs to implement bias mitigation techniques without significantly degrading overall performance. Propose a comprehensive architecture that addresses latency, fairness, and recommendation quality. Include specific model architectures, serving optimizations, and evaluation strategies.''',
];

void main() {
  silenceNativeStderr();
  final paths = TestPaths.resolve();

  for (final entry in {
    'short': _shortPrompts,
    'long': _longPrompts,
  }.entries) {
    final promptLabel = entry.key;
    final prompts = entry.value;

    test(
      'llama.cpp $promptLabel-prompt benchmark ($_runs runs)',
      skip: paths.llamaUnavailable ? 'llama model/library not found' : null,
      () async {
        final modelServer = await ModelServer.spawn();
        final brains = CowBrains<String>(
          libraryPath: paths.llamaLibraryPath,
          modelServer: modelServer,
        );

        final loaded = await brains.loadModel(
          modelPath: paths.llamaModelPath,
          modelOptions: const LlamaModelOptions(
            nGpuLayers: -1,
            useMmap: true,
          ),
          libraryPathOverride: paths.llamaLibraryPath,
        );

        final brain = brains.create('llama');
        await brain.init(
          modelHandle: loaded.modelPointer,
          options: LlamaCppRuntimeOptions(
            modelPath: paths.llamaModelPath,
            libraryPath: paths.llamaLibraryPath,
            contextOptions: const LlamaContextOptions(
              contextSize: 8192,
              nBatch: 512,
              nThreads: 4,
              nThreadsBatch: 4,
              useFlashAttn: true,
            ),
            modelOptions: const LlamaModelOptions(
              nGpuLayers: -1,
              useMmap: true,
            ),
            samplingOptions: defaultSamplingOptions,
            maxSequences: 4,
          ),
          profile: ModelProfileId.qwen3,
          tools: const [],
          settings: defaultSettings,
          enableReasoning: false,
          systemPrompt: 'You are a helpful assistant.',
        );

        await _runBenchmark('llama.cpp ($promptLabel)', brain, prompts);
        await brains.dispose();
      },
    );

    test(
      'MLX $promptLabel-prompt benchmark ($_runs runs)',
      skip: paths.mlxUnavailable ? 'MLX model/library not found' : null,
      () async {
        final modelServer = await ModelServer.spawn();
        final brains = CowBrains<String>(
          libraryPath: paths.mlxLibraryPath,
          modelServer: modelServer,
        );

        final loaded = await brains.loadModel(
          modelPath: paths.mlxModelPath,
          backend: InferenceBackend.mlx,
          libraryPathOverride: paths.mlxLibraryPath,
        );

        final brain = brains.create('mlx');
        await brain.init(
          modelHandle: loaded.modelPointer,
          options: MlxRuntimeOptions(
            modelPath: paths.mlxModelPath,
            libraryPath: paths.mlxLibraryPath,
            contextSize: 8192,
            samplingOptions: defaultSamplingOptions,
            maxSequences: 4,
          ),
          profile: ModelProfileId.qwen3,
          tools: const [],
          settings: defaultSettings,
          enableReasoning: false,
          systemPrompt: 'You are a helpful assistant.',
        );

        await _runBenchmark('MLX ($promptLabel)', brain, prompts);
        await brains.dispose();
      },
    );
  }
}

Future<void> _runBenchmark(
  String label,
  CowBrain brain,
  List<String> prompts,
) async {
  final seqTimes = <double>[];
  final concTimes = <double>[];
  final seqTokSec = <double>[];
  final concTokSec = <double>[];

  for (var run = 0; run < _runs + 1; run++) {
    brain.reset();

    var seqTokens = 0;
    final seqSw = Stopwatch()..start();
    for (final prompt in prompts) {
      final result = await collectTurn(brain, prompt);
      seqTokens += result.tokens;
    }
    seqSw.stop();

    brain
      ..reset()
      ..createSequence(sequenceId: 1)
      ..createSequence(sequenceId: 2);

    final concSw = Stopwatch()..start();
    final concResults = await Future.wait([
      collectTurn(brain, prompts[0]),
      collectTurn(brain, prompts[1], sequenceId: 1),
      collectTurn(brain, prompts[2], sequenceId: 2),
    ]);
    concSw.stop();

    final concTokens = concResults.fold(0, (sum, r) => sum + r.tokens);

    brain
      ..destroySequence(1)
      ..destroySequence(2);

    final seqS = seqSw.elapsedMilliseconds / 1000;
    final concS = concSw.elapsedMilliseconds / 1000;
    final speedup = seqS / concS;
    final seqTs = seqTokens / seqS;
    final concTs = concTokens / concS;

    if (run == 0) {
      stdout.writeln(
        '\n  $label — warmup (discarded): '
        'seq ${seqS.toStringAsFixed(2)}s (${seqTs.toStringAsFixed(1)} tok/s), '
        'conc ${concS.toStringAsFixed(2)}s (${concTs.toStringAsFixed(1)} tok/s), '
        '${speedup.toStringAsFixed(2)}x',
      );
    } else {
      seqTimes.add(seqS);
      concTimes.add(concS);
      seqTokSec.add(seqTs);
      concTokSec.add(concTs);
      stdout.writeln(
        '  $label — run $run: '
        'seq ${seqS.toStringAsFixed(2)}s (${seqTs.toStringAsFixed(1)} tok/s), '
        'conc ${concS.toStringAsFixed(2)}s (${concTs.toStringAsFixed(1)} tok/s), '
        '${speedup.toStringAsFixed(2)}x',
      );
    }
  }

  final avgSeq = seqTimes.reduce((a, b) => a + b) / seqTimes.length;
  final avgConc = concTimes.reduce((a, b) => a + b) / concTimes.length;
  final avgSpeedup = avgSeq / avgConc;
  final avgSeqTs = seqTokSec.reduce((a, b) => a + b) / seqTokSec.length;
  final avgConcTs = concTokSec.reduce((a, b) => a + b) / concTokSec.length;

  seqTimes.sort();
  concTimes.sort();
  seqTokSec.sort();
  concTokSec.sort();
  final medSeq = seqTimes[seqTimes.length ~/ 2];
  final medConc = concTimes[concTimes.length ~/ 2];
  final medSpeedup = medSeq / medConc;
  final medSeqTs = seqTokSec[seqTokSec.length ~/ 2];
  final medConcTs = concTokSec[concTokSec.length ~/ 2];

  stdout
    ..writeln(
      '\n  $label — avg ($_runs runs): '
      'seq ${avgSeq.toStringAsFixed(2)}s (${avgSeqTs.toStringAsFixed(1)} tok/s), '
      'conc ${avgConc.toStringAsFixed(2)}s (${avgConcTs.toStringAsFixed(1)} tok/s), '
      'speedup ${avgSpeedup.toStringAsFixed(2)}x',
    )
    ..writeln(
      '  $label — median: '
      'seq ${medSeq.toStringAsFixed(2)}s (${medSeqTs.toStringAsFixed(1)} tok/s), '
      'conc ${medConc.toStringAsFixed(2)}s (${medConcTs.toStringAsFixed(1)} tok/s), '
      'speedup ${medSpeedup.toStringAsFixed(2)}x',
    );
}
