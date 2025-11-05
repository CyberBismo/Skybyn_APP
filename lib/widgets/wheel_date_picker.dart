import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';

class WheelDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime>? onChanged;

  const WheelDatePicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.onChanged,
  });

  @override
  State<WheelDatePicker> createState() => _WheelDatePickerState();
}

class _WheelDatePickerState extends State<WheelDatePicker> {
  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _dayController;

  late List<int> _years;
  static const double _itemExtent = 40.0;

  @override
  void initState() {
    super.initState();
    _years = List<int>.generate(
      widget.lastDate.year - widget.firstDate.year + 1,
      (index) => widget.firstDate.year + index,
    );

    final clampedInitial = _clampDate(widget.initialDate);
    _selectedYear = clampedInitial.year;
    _selectedMonth = clampedInitial.month;
    _selectedDay = clampedInitial.day;

    _yearController = FixedExtentScrollController(initialItem: _years.indexOf(_selectedYear));
    _monthController = FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  DateTime _clampDate(DateTime date) {
    if (date.isBefore(widget.firstDate)) return widget.firstDate;
    if (date.isAfter(widget.lastDate)) return widget.lastDate;
    return date;
  }

  int _daysInMonth(int year, int month) {
    if (month == 12) {
      return DateTime(year + 1, 1, 0).day;
    }
    return DateTime(year, month + 1, 0).day;
  }

  void _notifyChanged() {
    final current = DateTime(_selectedYear, _selectedMonth, _selectedDay);
    widget.onChanged?.call(current);
  }

  void _onYearChanged(int index) {
    setState(() {
      _selectedYear = _years[index];
      final maxDay = _daysInMonth(_selectedYear, _selectedMonth);
      if (_selectedDay > maxDay) {
        _selectedDay = maxDay;
        _dayController.jumpToItem(_selectedDay - 1);
      }
      _enforceBounds();
    });
    _notifyChanged();
  }

  void _onMonthChanged(int index) {
    setState(() {
      _selectedMonth = index + 1;
      final maxDay = _daysInMonth(_selectedYear, _selectedMonth);
      if (_selectedDay > maxDay) {
        _selectedDay = maxDay;
        _dayController.jumpToItem(_selectedDay - 1);
      }
      _enforceBounds();
    });
    _notifyChanged();
  }

  void _onDayChanged(int index) {
    setState(() {
      _selectedDay = index + 1;
      _enforceBounds();
    });
    _notifyChanged();
  }

  void _enforceBounds() {
    final candidate = DateTime(_selectedYear, _selectedMonth, _selectedDay);
    if (candidate.isBefore(widget.firstDate)) {
      _selectedYear = widget.firstDate.year;
      _selectedMonth = widget.firstDate.month;
      _selectedDay = widget.firstDate.day;
      _syncControllers();
    } else if (candidate.isAfter(widget.lastDate)) {
      _selectedYear = widget.lastDate.year;
      _selectedMonth = widget.lastDate.month;
      _selectedDay = widget.lastDate.day;
      _syncControllers();
    }
  }

  void _syncControllers() {
    _yearController.jumpToItem(_years.indexOf(_selectedYear));
    _monthController.jumpToItem(_selectedMonth - 1);
    _dayController.jumpToItem(_selectedDay - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const textColor = Colors.white;

    const monthNames = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final days = _daysInMonth(_selectedYear, _selectedMonth);

    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: CupertinoPicker(
                scrollController: _monthController,
                itemExtent: _itemExtent,
                useMagnifier: true,
                magnification: 1.05,
                squeeze: 1.2,
                onSelectedItemChanged: _onMonthChanged,
                looping: true,
                selectionOverlay: const SizedBox.shrink(),
                children: List<Widget>.generate(12, (index) {
                  final isSelected = _selectedMonth == index + 1;
                  return Center(
                    child: Text(
                      monthNames[index],
                      style: TextStyle(
                        fontSize: 18,
                        color: textColor,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController: _dayController,
                itemExtent: _itemExtent,
                useMagnifier: true,
                magnification: 1.05,
                squeeze: 1.2,
                onSelectedItemChanged: _onDayChanged,
                looping: true,
                selectionOverlay: const SizedBox.shrink(),
                children: List<Widget>.generate(days, (index) {
                  final day = index + 1;
                  final isSelected = _selectedDay == day;
                  return Center(
                    child: Text(
                      day.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 18,
                        color: textColor,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController: _yearController,
                itemExtent: _itemExtent,
                useMagnifier: true,
                magnification: 1.05,
                squeeze: 1.2,
                onSelectedItemChanged: _onYearChanged,
                looping: false,
                selectionOverlay: const SizedBox.shrink(),
                children: List<Widget>.generate(_years.length, (index) {
                  final year = _years[index];
                  final isSelected = _selectedYear == year;
                  return Center(
                    child: Text(
                      year.toString(),
                      style: TextStyle(
                        fontSize: 18,
                        color: textColor,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        IgnorePointer(
          ignoring: true,
          child: Column(
            children: [
              Expanded(child: Container(color: Colors.transparent)),
              Container(
                height: _itemExtent,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),
                    bottom: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),
                  ),
                ),
              ),
              Expanded(child: Container(color: Colors.transparent)),
            ],
          ),
        ),
      ],
    );
  }
}

Future<DateTime?> showWheelDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final DateTime now = DateTime.now();
  final DateTime defaultInitial = initialDate ?? DateTime(now.year - 15, now.month, now.day);
  final DateTime minDate = firstDate ?? DateTime(now.year - 100, now.month, now.day);
  final DateTime maxDate = lastDate ?? DateTime(now.year - 15, now.month, now.day);

  DateTime temp = defaultInitial;

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: TranslatedText(TranslationKeys.cancel),
                    ),
                    const Spacer(),
                    TranslatedText(
                      TranslationKeys.selectDate,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(temp),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: TranslatedText(TranslationKeys.done),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 220,
                child: WheelDatePicker(
                  initialDate: defaultInitial,
                  firstDate: minDate,
                  lastDate: maxDate,
                  onChanged: (d) => temp = d,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}


