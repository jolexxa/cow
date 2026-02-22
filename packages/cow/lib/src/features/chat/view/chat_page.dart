import 'dart:async';

import 'package:blocterm/blocterm.dart';
import 'package:cow/src/app/app_info.dart';
import 'package:cow/src/app/session_log.dart';
import 'package:cow/src/features/chat/components/components.dart';
import 'package:cow/src/features/chat/state/state.dart';
import 'package:cow_brain/cow_brain.dart';
import 'package:nocterm/nocterm.dart';

class ChatPageView extends StatelessComponent {
  const ChatPageView({super.key});

  @override
  Component build(BuildContext context) {
    final appInfo = AppInfo.of(context);
    final sessionLog = Provider.of<SessionLog>(context);
    return BlocProvider<ChatCubit>.create(
      create: (context) {
        final brains = CowBrains<String>(
          libraryPath: appInfo.primaryOptions.libraryPath,
          modelServer: appInfo.modelServer,
        );
        final primaryBrain = brains.create(ChatCubit.primaryBrainKey);
        final lightweightBrain = brains.create(ChatCubit.lightweightBrainKey);
        final summaryBrain = SummaryBrain(brain: lightweightBrain);
        final chatData = ChatData()
          ..enableReasoning = appInfo.modelProfile.supportsReasoning;
        final summaryLogic = SummaryLogic(chatData: chatData);
        final toolExecutor = ToolExecutor(
          toolRegistry: appInfo.toolRegistry,
          brain: primaryBrain,
        );
        final logic = ChatLogic(chatData: chatData, brain: primaryBrain);
        final chatCubit = ChatCubit(
          logic: logic,
          toolRegistry: appInfo.toolRegistry,
          primaryOptions: appInfo.primaryOptions,
          modelProfile: appInfo.modelProfile,
          summaryOptions: appInfo.summaryOptions,
          summaryModelProfile: appInfo.summaryModelProfile,
          brains: brains,
          primaryBrain: primaryBrain,
          summaryBrain: summaryBrain,
          summaryLogic: summaryLogic,
          toolExecutor: toolExecutor,
          sessionLog: sessionLog,
        );
        unawaited(Future.microtask(chatCubit.initialize));
        return chatCubit;
      },
      child: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulComponent {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final AutoScrollController _scrollController = AutoScrollController();
  final AutoScrollController _reasoningScrollController =
      AutoScrollController();
  final TextEditingController _textController = TextEditingController();

  late final ChatCubit _session;

  @override
  void initState() {
    super.initState();
    _session = BlocProvider.of<ChatCubit>(context, listen: false);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _reasoningScrollController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(
    KeyboardEvent event,
    ChatState state,
    bool supportsReasoning,
  ) {
    if (event.matches(LogicalKey.keyC, ctrl: true)) {
      AppInfo.of(context).platform.exit();
      return true;
    }
    if (event.matches(LogicalKey.keyR, ctrl: true) && !state.generating) {
      _session
        ..clear()
        ..reset();
      return true;
    }
    if (supportsReasoning && event.matches(LogicalKey.tab, shift: true)) {
      _session.toggleReasoning();
      return true;
    }
    return false;
  }

  void _sendMessage(ChatState state) {
    if (state.loading || state.generating) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _session.submit(text);
  }

  Component _buildMessageList({
    required TuiThemeData theme,
    required List<ChatMessage> messages,
    required AutoScrollController controller,
    required int lastAssistantIndex,
    required bool showSpinner,
    required bool generating,
    required String emptyLabel,
    bool showSender = true,
    Color? scrollbarTrackColor,
    Color? scrollbarThumbColor,
  }) {
    final itemCount = messages.isEmpty ? 1 : messages.length;
    return Container(
      color: theme.background,
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        trackColor: scrollbarTrackColor,
        thumbColor: scrollbarThumbColor,
        child: Padding(
          padding: const EdgeInsets.only(right: 1),
          child: SelectionArea(
            onSelectionCompleted: ClipboardManager.copy,
            child: ListView.builder(
              cacheExtent: 20,
              controller: controller,
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (messages.isEmpty) {
                  return Center(child: Text(emptyLabel));
                }
                final message = messages[index];
                final shouldShowSpinner =
                    showSpinner &&
                    generating &&
                    index == lastAssistantIndex &&
                    message.sender == 'Cow' &&
                    !message.isSystem;
                return MessageItem(
                  message: message,
                  showSpinner: shouldShowSpinner,
                  showSender: showSender,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Component _buildChatList({
    required TuiThemeData theme,
    required ChatState state,
  }) {
    // Handle loading state with progress bar.
    if (state is InitializingState) {
      final progress = state.data.modelLoadProgress;
      if (progress != null) {
        return Container(
          color: theme.background,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: Padding(
              padding: const EdgeInsets.only(right: 1),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: 1,
                itemBuilder: (context, index) =>
                    LoadingProgressItem(progress: progress),
              ),
            ),
          ),
        );
      }
      // Fallback if no progress yet.
      return Container(
        color: theme.background,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: Padding(
            padding: const EdgeInsets.only(right: 1),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: 1,
              itemBuilder: (context, index) => MessageItem(
                message: ChatMessage.alert('Loading models...'),
                showSpinner: true,
              ),
            ),
          ),
        ),
      );
    }

    final visibleMessages = state.visibleMessages;
    final lastAssistantIndex = visibleMessages.lastIndexWhere(
      (message) => message.sender == 'Cow' && !message.isSystem,
    );
    return _buildMessageList(
      theme: theme,
      messages: visibleMessages,
      controller: _scrollController,
      lastAssistantIndex: lastAssistantIndex,
      showSpinner: true,
      generating: state.generating,
      emptyLabel: 'No messages yet.',
    );
  }

  Component _buildReasoningList({
    required TuiThemeData theme,
    required ChatState state,
  }) {
    return _buildMessageList(
      theme: theme,
      messages: state.reasoningMessages,
      controller: _reasoningScrollController,
      lastAssistantIndex: -1,
      showSpinner: false,
      generating: state.generating,
      emptyLabel: 'Moo.',
      showSender: false,
    );
  }

  Color _statusColor(TuiThemeData theme, ChatState state) {
    if (state.error != null) return theme.error;
    if (state.generating) return theme.warning;
    return theme.success;
  }

  String _inputPlaceholder(ChatState state) {
    if (state.loading) return 'Loading model...';
    if (state.generating) return 'Generating...';
    return 'Type a message...';
  }

  bool _showReasoningPane(bool supportsReasoning, BoxConstraints constraints) {
    return supportsReasoning && constraints.maxWidth > 60;
  }

  Component _buildInputBubbles(ChatState state) {
    if (!state.generating) {
      return const SizedBox();
    }
    final showSpeakingBubbles =
        state.phase == ChatPhase.responding ||
        state.phase == ChatPhase.executingTool;
    final showThinkingBubbles =
        state.phase == ChatPhase.reasoning ||
        (state.enableReasoning && state.phase == ChatPhase.idle);
    if (showSpeakingBubbles) {
      return const CowSpeakingBubblesAnimated();
    }
    if (showThinkingBubbles) {
      return const CowThoughtBubblesAnimated();
    }
    return const SizedBox();
  }

  Component _idleThoughtBubbles(
    ChatState state,
    bool supportsReasoning,
  ) {
    if (!supportsReasoning || !state.enableReasoning || state.generating) {
      return const SizedBox();
    }
    return const CowThoughtBubbles();
  }

  Component _cowWidget(ChatState state) {
    return state.generating
        ? state.phase == ChatPhase.responding
              ? const CowIconTalkingAnimated()
              : const CowIconAnimated()
        : const CowIconStatic();
  }

  Component _buildInputRow({
    required TuiThemeData theme,
    required ChatState state,
    required bool supportsReasoning,
  }) {
    final idleThoughtBubbles = _idleThoughtBubbles(state, supportsReasoning);
    final bubbleWidget = _buildInputBubbles(state);
    final cowWidget = _cowWidget(state);
    return Container(
      color: theme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('> ', style: TextStyle(color: theme.primary)),
          Expanded(
            child: SizedBox(
              height: 6,
              child: TextField(
                controller: _textController,
                focused: true,
                enabled: !state.loading,
                style: TextStyle(color: theme.onSurface),
                maxLines: 6,
                placeholder: _inputPlaceholder(state),
                placeholderStyle: TextStyle(color: theme.onSurface),
                onSubmitted: (_) => _sendMessage(state),
              ),
            ),
          ),
          idleThoughtBubbles,
          bubbleWidget,
          cowWidget,
        ],
      ),
    );
  }

  Component _footerSpacer() {
    return const Text('  ');
  }

  List<_FooterAction> _footerActions(
    TuiThemeData theme,
    ChatState state,
    bool supportsReasoning,
  ) {
    final actions = <_FooterAction>[
      _FooterAction('[Enter] Send', theme.secondary),
    ];
    if (supportsReasoning) {
      actions.add(_FooterAction(_thinkLabel(state), _thinkColor(theme, state)));
    }
    actions.addAll([
      _FooterAction('[Ctrl+R] Reset', theme.secondary),
      _FooterAction('[Ctrl+C] Quit', theme.secondary),
    ]);
    return actions;
  }

  List<Component> _buildFooterChildren(
    TuiThemeData theme,
    ChatState state,
    bool supportsReasoning,
  ) {
    final actions = _footerActions(theme, state, supportsReasoning);
    final children = <Component>[];
    for (var i = 0; i < actions.length; i += 1) {
      if (i > 0) {
        children.add(_footerSpacer());
      }
      children.add(
        Text(
          actions[i].label,
          style: TextStyle(color: actions[i].color),
        ),
      );
    }
    return children;
  }

  Component _buildFooter({
    required TuiThemeData theme,
    required ChatState state,
    required bool supportsReasoning,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: theme.surface,
      child: Row(
        children: _buildFooterChildren(theme, state, supportsReasoning),
      ),
    );
  }

  String _thinkLabel(ChatState state) {
    return state.enableReasoning
        ? '[Shift+Tab] Think: ON'
        : '[Shift+Tab] Think: OFF';
  }

  Color _thinkColor(TuiThemeData theme, ChatState state) {
    return state.enableReasoning ? theme.success : theme.secondary;
  }

  String _contextStatsLabel(ChatState state) {
    final stats = state.stats;
    if (stats == null) {
      return '100% context left';
    }
    final percentLeft = stats.budgetTokens <= 0
        ? 100
        : (stats.remainingTokens * 100 / stats.budgetTokens).round();
    final clamped = percentLeft.clamp(0, 100);
    return '$clamped% context left';
  }

  Component _buildChatBody({
    required bool showReasoningPane,
    required Component chatList,
    required Component reasoningList,
  }) {
    if (!showReasoningPane) {
      return chatList;
    }
    return Row(
      children: [
        Expanded(flex: 2, child: chatList),
        const VerticalDivider(),
        Expanded(child: reasoningList),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final appInfo = AppInfo.of(context);
    final supportsReasoning = appInfo.modelProfile.supportsReasoning;

    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final chatList = _buildChatList(theme: theme, state: state);
            final reasoningList = _buildReasoningList(
              theme: theme,
              state: state,
            );
            return Container(
              color: theme.background,
              child: Focusable(
                focused: true,
                onKeyEvent: (event) =>
                    _handleKeyEvent(event, state, supportsReasoning),
                child: Container(
                  color: theme.background,
                  child: Column(
                    children: [
                      Container(
                        color: theme.surface,
                        child: Row(
                          children: [
                            Expanded(
                              child: const Text(
                                'Cow',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _contextStatsLabel(state),
                                style: TextStyle(color: theme.secondary),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                state.status.toUpperCase(),
                                style: TextStyle(
                                  color: _statusColor(theme, state),
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: _buildChatBody(
                          showReasoningPane: _showReasoningPane(
                            supportsReasoning,
                            constraints,
                          ),
                          chatList: chatList,
                          reasoningList: reasoningList,
                        ),
                      ),
                      const Divider(),
                      _buildInputRow(
                        theme: theme,
                        state: state,
                        supportsReasoning: supportsReasoning,
                      ),
                      _buildFooter(
                        theme: theme,
                        state: state,
                        supportsReasoning: supportsReasoning,
                      ),
                      const SizedBox(height: 1),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

final class _FooterAction {
  const _FooterAction(this.label, this.color);

  final String label;
  final Color color;
}
