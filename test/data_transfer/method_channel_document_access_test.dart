import 'dart:async';
import 'dart:io';

import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/data/method_channel_document_access.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/graph_import_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Канал и его методы — протокол с плагином DocumentAccessPlugin.kt.
  const channel = MethodChannel('software.doable.doable/document_access');
  const documentUri =
      'content://com.android.externalstorage.documents/document/'
      'primary%3ADownload%2FDoable%202026-10-18.jsonl.gz';

  void answer(Future<Object?> Function(MethodCall call) handler) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, handler);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  test('диалог сохранения получает имя по умолчанию и возвращает документ по его адресу', () async {
    final calls = <MethodCall>[];
    answer((call) async {
      calls.add(call);
      return documentUri;
    });

    final creation = await const MethodChannelDocumentAccess().createDocument(
      suggestedName: 'Doable 2026-10-18.jsonl.gz',
    );

    expect(calls.single.method, 'createDocument');
    expect(calls.single.arguments, {'name': 'Doable 2026-10-18.jsonl.gz'});
    expect(
      creation,
      isA<DocumentCreated>().having(
        (created) => created.document.uri,
        'адрес документа',
        documentUri,
      ),
    );
  });

  test('диалог, закрытый без выбора места, даёт отмену', () async {
    answer((_) async => null);

    final creation = await const MethodChannelDocumentAccess().createDocument(
      suggestedName: 'Doable 2026-10-18.jsonl.gz',
    );

    expect(creation, isA<DocumentCreationCancelled>());
  });

  test(
    'неоткрывшийся диалог даёт типизированный отказ вместо исключения',
    () async {
      answer((_) async => throw PlatformException(code: 'dialog_unavailable'));

      final creation = await const MethodChannelDocumentAccess().createDocument(
        suggestedName: 'Doable 2026-10-18.jsonl.gz',
      );

      expect(creation, isA<DocumentCreationFailed>());
    },
  );

  test('файл с данными, выбранный в диалоге, даёт исход существующего файла '
      'вместо отказа', () async {
    answer((_) async => throw PlatformException(code: 'existing_file'));

    final creation = await const MethodChannelDocumentAccess().createDocument(
      suggestedName: 'Doable 2026-10-18.jsonl.gz',
    );

    expect(creation, isA<ExistingFileChosen>());
  });

  test(
    'копирование передаёт путь файла и адрес документа и завершается записью',
    () async {
      final calls = <MethodCall>[];
      answer((call) async {
        calls.add(call);
        return null;
      });

      final write = await const MethodChannelDocumentAccess().writeDocument(
        const CreatedDocument(documentUri),
        source: File('/data/user/0/software.doable.doable/app_flutter/tmp/a'),
      );

      expect(calls.single.method, 'writeDocument');
      expect(calls.single.arguments, {
        'source': '/data/user/0/software.doable.doable/app_flutter/tmp/a',
        'document': documentUri,
      });
      expect(write, isA<DocumentWritten>());
    },
  );

  test(
    'отказ записи документа даёт типизированный отказ вместо исключения',
    () async {
      answer(
        (_) async => throw PlatformException(code: 'document_not_written'),
      );

      final write = await const MethodChannelDocumentAccess().writeDocument(
        const CreatedDocument(documentUri),
        source: File('/data/user/0/software.doable.doable/app_flutter/tmp/a'),
      );

      expect(write, isA<DocumentWriteFailed>());
    },
  );
  test('шаг завершения передаёт адрес документа и исход операции', () async {
    final calls = <MethodCall>[];
    answer((call) async {
      calls.add(call);
      return null;
    });

    await const MethodChannelDocumentAccess().finishDocument(
      const CreatedDocument(documentUri),
      outcome: CreatedDocumentOutcome.succeeded,
    );
    await const MethodChannelDocumentAccess().finishDocument(
      const CreatedDocument(documentUri),
      outcome: CreatedDocumentOutcome.failed,
    );

    expect(calls.map((call) => call.method), everyElement('finishDocument'));
    expect(calls.map((call) => call.arguments), [
      {'document': documentUri, 'succeeded': true},
      {'document': documentUri, 'succeeded': false},
    ]);
  });

  test('ошибка канала на шаге завершения не становится исключением', () async {
    answer((_) async => throw PlatformException(code: 'error'));

    await expectLater(
      const MethodChannelDocumentAccess().finishDocument(
        const CreatedDocument(documentUri),
        outcome: CreatedDocumentOutcome.failed,
      ),
      completes,
    );
  });

  test('диалог выбора возвращает открытый документ по его адресу', () async {
    final calls = <MethodCall>[];
    answer((call) async {
      calls.add(call);
      return documentUri;
    });

    final opening = await const MethodChannelDocumentAccess().openDocument();

    expect(calls.single.method, 'openDocument');
    expect(
      opening,
      isA<DocumentOpened>().having(
        (opened) => opened.document.uri,
        'адрес документа',
        documentUri,
      ),
    );
  });

  test('диалог выбора, закрытый без документа, даёт отмену', () async {
    answer((_) async => null);

    final opening = await const MethodChannelDocumentAccess().openDocument();

    expect(opening, isA<DocumentOpeningCancelled>());
  });

  test(
    'неоткрывшийся диалог выбора даёт типизированный отказ вместо исключения',
    () async {
      answer((_) async => throw PlatformException(code: 'dialog_unavailable'));

      final opening = await const MethodChannelDocumentAccess().openDocument();

      expect(opening, isA<DocumentOpeningFailed>());
    },
  );

  test('начало запрашивается порциями до пригодного заголовка, затем канал '
      'разрешает копирование без передачи остатка документа в Dart', () async {
    final calls = <MethodCall>[];
    final bytes = graphExportFileOf([referenceGraphFileLines().first]);
    final chunks = [
      Uint8List.fromList(bytes.sublist(0, 2)),
      Uint8List.fromList(bytes.sublist(2, 10)),
      Uint8List.fromList(bytes.sublist(10)),
    ].iterator;
    answer((call) async {
      calls.add(call);
      if (call.method == 'readDocumentPrefix') {
        expect(chunks.moveNext(), isTrue, reason: 'Остаток недоступен Dart');
        return chunks.current;
      }
      return null;
    });

    final read = const MethodChannelDocumentAccess().readDocument(
      const OpenedDocument(documentUri),
      destination: File(
        '/data/user/0/software.doable.doable/app_flutter/tmp/import-1',
      ),
      cancellation: Completer<void>().future,
    );
    addTearDown(read.finish);
    final file = await GraphFormatFile.read(read.prefix);
    await file.close();

    expect(calls.map((call) => call.method), [
      'beginDocumentRead',
      'readDocumentPrefix',
      'readDocumentPrefix',
      'readDocumentPrefix',
    ]);
    expect(calls.first.arguments, {
      'prefixLimit': documentPrefixByteLimit,
      'chunkSize': documentPrefixChunkSize,
      'document': documentUri,
      'destination':
          '/data/user/0/software.doable.doable/app_flutter/tmp/import-1',
    });
    expect(file.header.counts.intentions, 4);
    expect(await read.copy(), isA<DocumentCopied>());
    await read.finish();
    expect(calls.last.method, 'copyReadDocument');
    expect(
      calls.skip(1).map((call) => call.arguments),
      everyElement({
        'destination':
            '/data/user/0/software.doable.doable/app_flutter/tmp/import-1',
      }),
    );
  });

  test('заголовок новой версии завершает сессию без разрешения копирования '
      'и без чтения остатка', () async {
    final calls = <MethodCall>[];
    answer((call) async {
      calls.add(call);
      if (call.method == 'readDocumentPrefix') {
        return Uint8List.fromList(newerFormatVersionFile());
      }
      return null;
    });
    final read = const MethodChannelDocumentAccess().readDocument(
      const OpenedDocument(documentUri),
      destination: File('/tmp/import-newer'),
      cancellation: Completer<void>().future,
    );

    try {
      await expectLater(
        GraphFormatFile.read(read.prefix),
        throwsA(isA<GraphFormatVersionTooNew>()),
      );
    } finally {
      await read.finish();
    }
    await read.finish();

    expect(calls.map((call) => call.method), [
      'beginDocumentRead',
      'readDocumentPrefix',
      'finishDocumentRead',
    ]);
    expect(calls.last.arguments, {'destination': '/tmp/import-newer'});
  });

  for (final (method, code, failure) in [
    ('beginDocumentRead', 'document_not_read', DocumentReadFailure.unreadable),
    ('readDocumentPrefix', 'document_not_read', DocumentReadFailure.unreadable),
    ('readDocumentPrefix', 'copy_cancelled', DocumentReadFailure.cancelled),
    ('readDocumentPrefix', 'error', DocumentReadFailure.unknown),
  ]) {
    test('отказ $method с кодом $code становится типизированным отказом '
        'чтения и завершает сессию без копирования', () async {
      final calls = <MethodCall>[];
      answer((call) async {
        calls.add(call);
        if (call.method == method) throw PlatformException(code: code);
        return null;
      });
      final read = const MethodChannelDocumentAccess().readDocument(
        const OpenedDocument(documentUri),
        destination: File('/tmp/import-unread'),
        cancellation: Completer<void>().future,
      );

      await expectLater(read.prefix.drain<void>(), throwsA(failure));
      await read.finish();

      expect(calls.last.method, 'finishDocumentRead');
      expect(
        calls.map((call) => call.method),
        isNot(contains('copyReadDocument')),
      );
    });
  }

  test('канал прекращает запросы начала по достижении 64 КиБ', () async {
    var bytesRead = 0;
    answer((call) async {
      if (call.method == 'readDocumentPrefix') {
        bytesRead += documentPrefixChunkSize;
        return Uint8List(documentPrefixChunkSize);
      }
      return null;
    });
    final read = const MethodChannelDocumentAccess().readDocument(
      const OpenedDocument(documentUri),
      destination: File('/tmp/import-limit'),
      cancellation: Completer<void>().future,
    );

    await read.prefix.drain<void>();
    await read.finish();

    expect(bytesRead, documentPrefixByteLimit);
  });

  for (final readingPrefix in [true, false]) {
    test('отмена ${readingPrefix ? 'чтения начала' : 'ожидания решения'} '
        'передаёт путь сессии и завершает её без копирования', () async {
      final calls = <MethodCall>[];
      final prefixRequested = Completer<void>();
      final cancelled = Completer<void>();
      answer((call) async {
        calls.add(call);
        switch (call.method) {
          case 'readDocumentPrefix':
            prefixRequested.complete();
            if (!readingPrefix) return Uint8List.fromList([0x1f, 0x8b]);
            await cancelled.future;
            throw PlatformException(code: 'copy_cancelled');
          case 'cancelCopy':
            cancelled.complete();
        }
        return null;
      });
      final cancellation = Completer<void>();
      final read = const MethodChannelDocumentAccess().readDocument(
        const OpenedDocument(documentUri),
        destination: File('/tmp/import-cancelled'),
        cancellation: cancellation.future,
      );
      final prefix = readingPrefix
          ? read.prefix.drain<void>()
          : read.prefix.first;
      final assertion = readingPrefix
          ? expectLater(prefix, throwsA(DocumentReadFailure.cancelled))
          : expectLater(prefix, completion([0x1f, 0x8b]));
      await prefixRequested.future;
      if (!readingPrefix) await assertion;

      cancellation.complete();
      await cancelled.future;
      await assertion;
      await read.finish();

      expect(calls.map((call) => call.method), [
        'beginDocumentRead',
        'readDocumentPrefix',
        'cancelCopy',
        'finishDocumentRead',
      ]);
      expect(calls.last.arguments, {'destination': '/tmp/import-cancelled'});
    });
  }

  for (final (code, outcome) in [
    ('document_not_read', isA<DocumentNotRead>()),
    ('storage_full', isA<DocumentCopyStorageFull>()),
    ('copy_not_written', isA<DocumentCopyFailed>()),
    ('error', isA<DocumentCopyFailed>()),
  ]) {
    test('отказ копирования с кодом $code даёт типизированный исход вместо '
        'исключения', () async {
      answer((call) async {
        if (call.method == 'copyReadDocument') {
          throw PlatformException(code: code);
        }
        return null;
      });

      final copy = await const MethodChannelDocumentAccess()
          .readDocument(
            const OpenedDocument(documentUri),
            destination: File(
              '/data/user/0/software.doable.doable/app_flutter/tmp/import-1',
            ),
            cancellation: Completer<void>().future,
          )
          .copy();

      expect(copy, outcome);
    });
  }

  test(
    'отмена передаёт плагину путь копии, и копирование завершается отменой',
    () async {
      final cancelCalls = <MethodCall>[];
      final cancelled = Completer<void>();
      answer((call) async {
        switch (call.method) {
          case 'copyReadDocument':
            // Плагин сообщает исход копирования, когда принял отмену.
            await cancelled.future;
            throw PlatformException(code: 'copy_cancelled');
          case 'cancelCopy':
            cancelCalls.add(call);
            cancelled.complete();
        }
        return null;
      });
      final cancellation = Completer<void>();

      final copying = const MethodChannelDocumentAccess()
          .readDocument(
            const OpenedDocument(documentUri),
            destination: File(
              '/data/user/0/software.doable.doable/app_flutter/tmp/import-1',
            ),
            cancellation: cancellation.future,
          )
          .copy();
      cancellation.complete();

      expect(await copying, isA<DocumentCopyCancelled>());
      expect(cancelCalls.single.arguments, {
        'destination':
            '/data/user/0/software.doable.doable/app_flutter/tmp/import-1',
      });
    },
  );
}
