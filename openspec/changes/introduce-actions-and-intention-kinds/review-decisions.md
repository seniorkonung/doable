# Решения по findings OpenSpec review

<!-- paseo-openspec-orchestrator:finding-decisions:v1 -->

Файл ведёт оркестратор. Решения приняты пользователем в сессии решений и исполняются автономно, по одной finding за сессию. Сессия исполнения удаляет раздел своей finding в коммите её устранения.

## F46 · Low — Критерий 2.4 делает единственное намерение пути простым текстом

- **Решение:** Устранить
- **Как устранить:** В tasks.md исправить критерий задачи 2.4: «Названия корня и промежуточных намерений — кнопки; в пути из одного намерения его название — кнопка корня; простым текстом остаётся только последнее намерение пути из двух и более намерений» (по action-paths «Сокращение пути и смена корня»), и указать, что тест компонента PathBuilder проверяет оба случая: единственное намерение — кнопка, последнее из двух и более — простой текст. В той же правке по-английски уточнить строку README context/doable-design-system/components/PathBuilder/README.md «The last step is plain text.» до формулировки вроде «The last step of a path of two or more steps is plain text; the only step of a one-step path is the root and stays a button.», так как 2.4 требует следовать README. Поведение продукта не меняется, спеки не правятся. Проверить: mise exec --no-deps -- openspec validate introduce-actions-and-intention-kinds --strict --no-interactive.
