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
  Future<DocumentCreation> createDocument({required String suggestedName});

  /// Копирует все байты файла [source] в документ [document].
  ///
  /// После отказа в документе может остаться часть байтов файла.
  Future<DocumentWrite> writeDocument(
    CreatedDocument document, {
    required File source,
  });
}

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
