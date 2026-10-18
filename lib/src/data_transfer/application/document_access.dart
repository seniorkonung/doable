import 'dart:io';

/// Документы вне каталога приложения, которые человек выбирает системными
/// диалогами Android, без разрешений приложения (ADR-0037).
///
/// Вызывающая сторона получает типизированный исход без исключений. Байты
/// документа не проходят через границу: данные копируются между документом и
/// файлом приложения на стороне платформы.
abstract interface class DocumentAccess {
  /// Открывает системный диалог сохранения документа с именем по умолчанию
  /// [suggestedName] и создаёт документ в выбранном человеком месте.
  ///
  /// Документ создаётся пустым. Если человек закрыл диалог или Activity
  /// приложения отсоединилась, пока диалог ожидал ответа, исход —
  /// [DocumentCreationCancelled]. Пока ожидается ответ одного диалога, второй
  /// не открывается и исход второго запроса — [DocumentCreationFailed].
  ///
  /// Право записи в созданный документ удерживается до [finishDocument],
  /// даже если движок приложения перенесён в другую Activity.
  Future<DocumentCreation> createDocument({required String suggestedName});

  /// Копирует все байты файла [source] в документ [document].
  ///
  /// После отказа в документе может остаться часть байтов файла.
  Future<DocumentWrite> writeDocument(
    CreatedDocument document, {
    required File source,
  });

  /// Завершает работу с документом [document] после исхода [outcome]
  /// операции, для которой он создан, и отпускает удерживаемое право на него.
  ///
  /// После отказа операции документ, созданный пустым или записанный
  /// частично, удаляется до того, как право отпущено, если поставщик это
  /// позволяет. После успеха документ остаётся.
  ///
  /// Вызывающая сторона завершает работу с каждым созданным документом один
  /// раз при любом исходе. Отказ удалить документ или отпустить право
  /// исключением не становится: документ остаётся у поставщика, а право,
  /// оставшееся у приложения, отпускается при следующем запуске.
  Future<void> finishDocument(
    CreatedDocument document, {
    required CreatedDocumentOutcome outcome,
  });
}

/// Исход операции, для которой создан документ.
enum CreatedDocumentOutcome { succeeded, failed }

/// Документ, созданный системным диалогом сохранения.
final class CreatedDocument {
  const CreatedDocument(this.uri);

  /// Адрес документа у его поставщика, непрозрачный для приложения. В
  /// диагностику не попадает: адрес может содержать имя файла и папки.
  final String uri;
}

/// Исход системного диалога сохранения.
sealed class DocumentCreation {
  const DocumentCreation();
}

final class DocumentCreated extends DocumentCreation {
  const DocumentCreated(this.document);

  final CreatedDocument document;
}

/// Человек не выбрал место документа; отказом это не считается.
final class DocumentCreationCancelled extends DocumentCreation {
  const DocumentCreationCancelled();
}

/// Системный диалог сохранения не открылся.
final class DocumentCreationFailed extends DocumentCreation {
  const DocumentCreationFailed();
}

/// Исход копирования файла в документ.
sealed class DocumentWrite {
  const DocumentWrite();
}

final class DocumentWritten extends DocumentWrite {
  const DocumentWritten();
}

/// Документ не записан: поставщик документа не открыл его для записи или
/// запись прервалась, например из-за отозванного доступа или нехватки места.
final class DocumentWriteFailed extends DocumentWrite {
  const DocumentWriteFailed();
}
