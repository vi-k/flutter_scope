import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import 'console.dart';

class ConsoleView extends StatefulWidget {
  final Object source;

  const ConsoleView({
    super.key,
    required this.source,
  });

  @override
  State<ConsoleView> createState() => _ConsoleSourceViewState();
}

class _ConsoleSourceViewState extends State<ConsoleView> {
  final _scrollController = ScrollController();
  late final ListenableSelectSubscription<void> _subscription;
  bool _firstFrame = true;

  @override
  void initState() {
    super.initState();
    _subscription = console.select(
      (console) => console.lines(widget.source),
      (_, __) {
        _scrollToBottom();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      // Through `setState`, because the flag decides what the build shows and
      // nothing else asks for a rebuild here: a console with no new line to
      // report kept the view at `Opacity(0)`, so a tab entered a second time
      // looked empty until something happened to log.
      setState(() {
        _firstFrame = false;
      });

      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _scrollToBottom() {
    // The new lines have to be on screen before there is anything to
    // scroll to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style.copyWith(
            fontSize: 10,
            color: Colors.blueGrey.shade200,
          ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 80),
        child: ColoredBox(
          color: Colors.blueGrey.shade900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListenableSelector(
                        listenable: console,
                        selector: (console) => console.lines(widget.source),
                        builder: (context, console, lines, ___) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(2, 2, 0, 8),
                            controller: _scrollController,
                            child: Opacity(
                              opacity: _firstFrame ? 0 : 1,
                              child: SelectableText(lines.join('\n')),
                            ),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      color: Colors.grey,
                      iconSize: 12,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => console.clear(widget.source),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
