import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/daily_choice_priority.dart';
import '../../domain/daily_choice_schedule.dart';

/// Общий ввод планирования; черновиком и отправкой владеет модель формы.
final class DailyChoicePlanningFields extends StatelessWidget {
  const DailyChoicePlanningFields({
    required this.schedule,
    required this.priority,
    required this.enabled,
    required this.onScheduleChanged,
    required this.onPriorityChanged,
    super.key,
  });

  final DailyChoiceSchedule schedule;
  final DailyChoicePriority priority;
  final bool enabled;
  final ValueChanged<DailyChoiceSchedule> onScheduleChanged;
  final ValueChanged<DailyChoicePriority> onPriorityChanged;

  Future<void> _pickTime(BuildContext context) async {
    final time = await showDialog<DailyChoiceTime>(
      context: context,
      builder: (_) => _TimeInputDialog(schedule: schedule),
    );
    if (!context.mounted || time == null) return;
    onScheduleChanged(time);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timeLabel = switch (schedule) {
      DailyChoiceAllDay() => l10n.dailyChoiceSetTime,
      DailyChoiceTime(:final hour, :final minute) => l10n.dailyChoiceTimeLabel(
        TimeOfDay(hour: hour, minute: minute).format(context),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dailyChoiceScheduleLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.dailyChoiceAllDay),
              selected: schedule is DailyChoiceAllDay,
              onSelected: enabled
                  ? (_) => onScheduleChanged(const DailyChoiceAllDay())
                  : null,
            ),
            ChoiceChip(
              label: Text(timeLabel),
              selected: schedule is DailyChoiceTime,
              onSelected: enabled ? (_) => _pickTime(context) : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.dailyChoicePriorityLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in DailyChoicePriority.values)
              ChoiceChip(
                label: Text(
                  l10n.dailyChoicePriorityOption(value.name.toUpperCase()),
                ),
                selected: value == priority,
                onSelected: enabled ? (_) => onPriorityChanged(value) : null,
              ),
          ],
        ),
      ],
    );
  }
}

final class _TimeInputDialog extends StatefulWidget {
  const _TimeInputDialog({required this.schedule});

  final DailyChoiceSchedule schedule;

  @override
  State<_TimeInputDialog> createState() => _TimeInputDialogState();
}

final class _TimeInputDialogState extends State<_TimeInputDialog> {
  final _formKey = GlobalKey<FormState>();
  late int _hour;
  late int _minute;

  String? _validate(String? text, int maximum) {
    final value = int.tryParse(text ?? '');
    return value != null && value >= 0 && value <= maximum
        ? null
        : MaterialLocalizations.of(context).invalidTimeLabel;
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    Navigator.of(context).pop(DailyChoiceTime(hour: _hour, minute: _minute));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final time = switch (widget.schedule) {
      DailyChoiceAllDay() => null,
      DailyChoiceTime time => time,
    };
    return AlertDialog(
      scrollable: true,
      title: Text(AppLocalizations.of(context).dailyChoiceSetTime),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: time?.hour.toString().padLeft(2, '0'),
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.timePickerHourLabel,
                helperText: '0–23',
                errorMaxLines: 3,
              ),
              validator: (text) => _validate(text, 23),
              onSaved: (text) => _hour = int.parse(text!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: time?.minute.toString().padLeft(2, '0'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.timePickerMinuteLabel,
                helperText: '0–59',
                errorMaxLines: 3,
              ),
              validator: (text) => _validate(text, 59),
              onSaved: (text) => _minute = int.parse(text!),
              onFieldSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButtonLabel),
        ),
        TextButton(onPressed: _confirm, child: Text(l10n.okButtonLabel)),
      ],
    );
  }
}
