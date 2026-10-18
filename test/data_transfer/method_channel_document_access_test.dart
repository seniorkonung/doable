import 'dart:io';

import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/data_transfer/data/method_channel_document_access.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
