## ADDED Requirements

### Requirement: CI job использует только объявленный набор инструментов
Каждый CI job SHALL получать инструменты только из своего setup-шага
`mise-action` и SHALL NOT автоматически устанавливать остальные инструменты,
объявленные в корневом `mise.toml`, при выполнении рабочих команд job.

#### Scenario: OpenSpec-проверка выполняется без Flutter
- **GIVEN** setup-шаг OpenSpec job установил Node.js и OpenSpec
- **WHEN** job запускает строгую валидацию OpenSpec
- **THEN** валидация выполняется экспортированными setup-шагом инструментами
- **THEN** Flutter, APM и Lefthook не устанавливаются

#### Scenario: Проектная проверка выполняется с частичным Flutter toolchain
- **GIVEN** setup-шаг project job установил Flutter
- **WHEN** job запускает задачи проверки из `mise.toml`
- **THEN** задачи используют установленный Flutter и входящий в него Dart
- **THEN** Node.js, OpenSpec, APM и Lefthook не устанавливаются

### Requirement: Частичные установки кэшируются независимо
Каждый setup-шаг `mise-action` SHALL восстанавливать и сохранять стандартный
кэш для собственного значения `install_args`. Cache miss SHALL приводить к
установке только объявленной группы инструментов и SHALL NOT объединять кэши
разных частичных toolchain под общим ключом.

#### Scenario: Cache miss OpenSpec toolchain
- **GIVEN** для Node.js и OpenSpec нет доступного точного ключа кэша
- **WHEN** выполняется setup-шаг OpenSpec job
- **THEN** устанавливаются и сохраняются Node.js и OpenSpec
- **THEN** остальные инструменты проекта не добавляются в этот кэш

#### Scenario: Точный кэш доступен job
- **GIVEN** стандартный точный ключ частичного toolchain доступен текущему job
- **WHEN** выполняется соответствующий setup-шаг
- **THEN** action восстанавливает этот кэш перед рабочими командами job
- **THEN** рабочие команды не расширяют восстановленный набор инструментов
