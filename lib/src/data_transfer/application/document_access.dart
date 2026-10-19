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
  /// Документ создаётся пустым, но диалог позволяет выбрать и существующий
  /// файл, подтвердив его замену. Файл, о котором поставщик сообщил, что он не
  /// пуст, документом не становится, исход — [ExistingFileChosen]; файл,
  /// размер которого поставщик не сообщил, становится документом. Если
  /// человек закрыл диалог или Activity приложения отсоединилась, пока диалог
  /// ожидал ответа, исход — [DocumentCreationCancelled]. Пока ожидается ответ
  /// одного диалога, второй не открывается и исход второго запроса —
  /// [DocumentCreationFailed].
  ///
  /// Право записи в созданный документ удерживается до [finishDocument],
  /// даже если движок приложения перенесён в другую Activity.
  Future<DocumentCreation> createDocument({required String suggestedName});

  /// Копирует все байты файла [source] в документ [document] вместо его
  /// прежнего содержимого.
  ///
  /// После отказа в документе может остаться часть байтов файла.
  Future<DocumentWrite> writeDocument(
    CreatedDocument document, {
    required File source,
  });

  /// Завершает работу с документом [document] после исхода [outcome]
  /// операции, для которой он создан, и отпускает удерживаемое право на него.
  ///
  /// После отказа операции документ, о котором поставщик при выборе сообщил,
  /// что он пуст, удаляется до того, как право отпущено, если поставщик это
  /// позволяет. Документ неизвестного размера остаётся: в нём могли быть
  /// данные. После успеха документ остаётся.
  ///
  /// Вызывающая сторона завершает работу с каждым созданным документом один
  /// раз при любом исходе. Отказ удалить документ или отпустить право
  /// исключением не становится: документ остаётся у поставщика, а право,
  /// оставшееся у приложения, отпускается при следующем запуске.
  Future<void> finishDocument(
    CreatedDocument document, {
    required CreatedDocumentOutcome outcome,
  });

  /// Открывает системный диалог выбора документа любого типа: часть
  /// поставщиков указывает тип документа неверно, а файл проверяется по
  /// содержимому.
  ///
  /// Если человек закрыл диалог или Activity приложения отсоединилась, пока
  /// диалог ожидал ответа, исход — [DocumentOpeningCancelled]. Пока
  /// ожидается ответ другого диалога, этот не открывается, и исход —
  /// [DocumentOpeningFailed].
  ///
  /// Право чтения открытого документа удерживается до конца его копирования
  /// [copyDocument], даже если движок приложения перенесён в другую
  /// Activity. Вызывающая сторона копирует каждый открытый документ один раз;
  /// право, которое осталось у приложения, отпускается при следующем запуске.
  Future<DocumentOpening> openDocument();

  /// Копирует все байты открытого документа [document] в файл приложения
  /// [destination] и при любом исходе отпускает право чтения документа.
  ///
  /// После отказа неполной копии нет. Завершение [cancellation] отменяет
  /// копирование: исход сразу становится [DocumentCopyCancelled], даже если
  /// поставщик документа держит его открытие или чтение и отмену не
  /// учитывает. Такой поставщик может ответить позже. Тогда брошенное
  /// копирование больше не пишет [destination], а удаляет его, и исход
  /// повторно не сообщается, поэтому у каждого копирования свой
  /// [destination]. Отмена после исхода ничего не меняет.
  Future<DocumentCopy> copyDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
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

/// Человек выбрал в диалоге файл с данными, например прежний файл экспорта,
/// и подтвердил его замену. Файл не меняется, а право на него не
/// удерживается, поэтому работа с ним не завершается.
final class ExistingFileChosen extends DocumentCreation {
  const ExistingFileChosen();
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

/// Документ, открытый системным диалогом выбора.
final class OpenedDocument {
  const OpenedDocument(this.uri);

  /// Адрес документа у его поставщика, непрозрачный для приложения. В
  /// диагностику не попадает: адрес может содержать имя файла и папки.
  final String uri;
}

/// Исход системного диалога выбора документа.
sealed class DocumentOpening {
  const DocumentOpening();
}

final class DocumentOpened extends DocumentOpening {
  const DocumentOpened(this.document);

  final OpenedDocument document;
}

/// Человек не выбрал документ; отказом это не считается.
final class DocumentOpeningCancelled extends DocumentOpening {
  const DocumentOpeningCancelled();
}

/// Системный диалог выбора не открылся.
final class DocumentOpeningFailed extends DocumentOpening {
  const DocumentOpeningFailed();
}

/// Исход копирования открытого документа в файл приложения.
sealed class DocumentCopy {
  const DocumentCopy();
}

final class DocumentCopied extends DocumentCopy {
  const DocumentCopied();
}

/// Документ не прочитан: поставщик документа не открыл его или чтение
/// прервалось, например облачный файл недоступен без сети, файл перемещён или
/// доступ к нему отозван.
final class DocumentNotRead extends DocumentCopy {
  const DocumentNotRead();
}

/// Копии не хватило места на устройстве.
final class DocumentCopyStorageFull extends DocumentCopy {
  const DocumentCopyStorageFull();
}

/// Копия не записана по другой причине.
final class DocumentCopyFailed extends DocumentCopy {
  const DocumentCopyFailed();
}

/// Копирование отменено; отказом это не считается.
final class DocumentCopyCancelled extends DocumentCopy {
  const DocumentCopyCancelled();
}
