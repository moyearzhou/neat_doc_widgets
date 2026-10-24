import 'dart:async';
import 'dart:isolate';

/// One cancellable CPU job. Payload is sent only after spawn completes, so a
/// cancelled startup cannot copy a document and begin work behind its owner.
/// Completion/cancellation waits for onExit before another job may be started.
class CancellableSearchTask {
  final ReceivePort _messages = ReceivePort();
  final ReceivePort _exit = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final Completer<void> _done = Completer<void>();
  final Completer<void> _exited = Completer<void>();
  Isolate? _isolate;
  bool _cancelled = false;
  bool _started = false;
  Object? _failure;
  late StackTrace _failureStack;

  Future<void> get stopped => _done.future;

  Future<void> run(
    void Function(List<Object?>) operation,
    Object? payload,
    void Function(Object?) onData,
  ) async {
    if (_cancelled) {
      return;
    }
    if (_started) {
      throw StateError('Search task is single-use');
    }
    _started = true;
    _exit.listen((_) {
      if (!_exited.isCompleted) {
        _exited.complete();
      }
    });
    _errors.listen((dynamic error) {
      _failure = RemoteError('${error[0]}', '${error[1]}');
      _failureStack = StackTrace.fromString('${error[1]}');
    });
    _messages.listen((dynamic message) {
      if (_cancelled) {
        return;
      }
      if (message is SendPort) {
        try {
          message.send(<Object?>[operation, payload]);
        } catch (error, stack) {
          _failure = error;
          _failureStack = stack;
          _isolate?.kill(priority: Isolate.immediate);
        }
      } else {
        try {
          onData(message);
        } catch (error, stack) {
          _failure = error;
          _failureStack = stack;
          _isolate?.kill(priority: Isolate.immediate);
        }
      }
    });
    try {
      final isolate = await Isolate.spawn(
        _startSearchTask,
        _messages.sendPort,
        onExit: _exit.sendPort,
        onError: _errors.sendPort,
      );
      _isolate = isolate;
      if (_cancelled) {
        isolate.kill(priority: Isolate.immediate);
      }
      await _exited.future;
      // Deliver result/error messages already queued before the exit signal.
      await Future<void>.delayed(Duration.zero);
      if (!_cancelled && _failure != null) {
        Error.throwWithStackTrace(_failure!, _failureStack);
      }
    } finally {
      _isolate = null;
      _messages.close();
      _exit.close();
      _errors.close();
      if (!_done.isCompleted) {
        _done.complete();
      }
    }
  }

  Future<void> cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    // A caller may cancel before its serialized turn has started.
    if (!_started && !_done.isCompleted) {
      _messages.close();
      _exit.close();
      _errors.close();
      _done.complete();
    }
    return stopped;
  }
}

void _startSearchTask(SendPort reply) {
  final input = ReceivePort();
  reply.send(input.sendPort);
  input.first.then((dynamic message) {
    input.close();
    final operation = message[0] as void Function(List<Object?>);
    operation(<Object?>[reply, message[1]]);
  });
}
