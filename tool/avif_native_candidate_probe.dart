// flutter_avif 3.1.0 Windows ABI probe. Compile and run in its own process.
// The candidate DLL is deliberately not bundled with the application.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 3) {
    stderr.writeln('Usage: avif-candidate-probe <DLL> <AVIF> [truncateBytes]');
    exitCode = 64;
    return;
  }
  if (!Platform.isWindows) {
    throw UnsupportedError('This probe targets the Windows candidate DLL.');
  }
  final allocator = DynamicLibrary.open('msvcrt.dll');
  final allocate = allocator
      .lookupFunction<
        Pointer<Void> Function(UintPtr),
        Pointer<Void> Function(int)
      >('malloc');
  final free = allocator
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final library = DynamicLibrary.open(args[0]);
  library.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('store_dart_post_cobject')(NativeApi.postCObject.cast());
  final decode = library
      .lookupFunction<
        Int64 Function(Int64, Pointer<Uint8>, UintPtr),
        int Function(int, Pointer<Uint8>, int)
      >('decode_single_frame_image');
  final sample = await File(args[1]).readAsBytes();
  final count = args.length == 3 ? int.parse(args[2]) : sample.length;
  if (count < 0 || count > sample.length) {
    throw ArgumentError('truncateBytes must be between 0 and ${sample.length}');
  }
  final input = sample.sublist(0, count);
  // KeyRequest protobuf field 2 is the image data (length-delimited).
  final length = <int>[];
  var remaining = input.length;
  do {
    final next = remaining & 127;
    remaining >>= 7;
    length.add(next | (remaining == 0 ? 0 : 128));
  } while (remaining != 0);
  final request = Uint8List.fromList([0x12, ...length, ...input]);
  final pointer = allocate(request.length).cast<Uint8>();
  if (pointer == nullptr) throw StateError('Unable to allocate probe request');
  final port = RawReceivePort();
  final done = Completer<Object?>();
  port.handler = (Object? value) {
    if (!done.isCompleted) done.complete(value);
  };
  try {
    pointer.asTypedList(request.length).setAll(0, request);
    try {
      // This ABI clones the request synchronously before dispatching work.
      decode(port.sendPort.nativePort, pointer, request.length);
    } finally {
      free(pointer.cast());
    }
    final reply = await done.future.timeout(const Duration(seconds: 3));
    stdout.writeln(
      jsonEncode({
        'sample': args[1],
        'inputBytes': count,
        'replied': true,
        'replyBytes': reply is Uint8List ? reply.length : null,
        'replyType': reply.runtimeType.toString(),
      }),
    );
  } on TimeoutException {
    stdout.writeln(
      jsonEncode({
        'sample': args[1],
        'inputBytes': count,
        'replied': false,
        'error': 'No native result or error reply within 3 seconds.',
      }),
    );
    exitCode = 2;
  } finally {
    port.close();
  }
}
