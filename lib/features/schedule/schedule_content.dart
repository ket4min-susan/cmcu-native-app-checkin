import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../theme/formatters.dart';
import '../../theme/motion.dart';
import '../../theme/campus_brand.dart';
import 'entry_card.dart';
import 'schedule_controller.dart';
import 'week_strip.dart';

class ScheduleContent extends StatefulWidget {
  const ScheduleContent({
    super.key,
    required this.controller,
    this.compact = false,
  });
  final ScheduleController controller;
  final bool compact;
  @override
  State<ScheduleContent> createState() => _ScheduleContentState();
}

class _ScheduleContentState extends State<ScheduleContent> {
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.query,
  );
  ScheduleController get c => widget.controller;
  @override
  void didUpdateWidget(covariant ScheduleContent old) {
    super.didUpdateWidget(old);
    if (old.controller != c) _search.text = c.query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: c.selectedDay,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Chọn ngày xem lịch',
    );
    if (selected != null && mounted) c.goToDate(selected);
  }

  void _clear() {
    _search.clear();
    c.resetFilters();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final entries = c.visibleEntries;
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: CustomScrollView(
        key: const PageStorageKey('schedule-scroll'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: _ScheduleHeading(lessonCount: c.entries.length),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: s.outlineVariant.withValues(alpha: .45),
                    ),
                  ),
                  child: WeekStrip(controller: c),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DayOverview(controller: c),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.weekOverview
                                  ? 'Lịch trong tuần'
                                  : dayTitle(c.selectedDay),
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _pickDate,
                            tooltip: 'Chọn ngày',
                            icon: const Icon(Icons.date_range_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('schedule-search'),
                        controller: _search,
                        onChanged: c.search,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Tìm môn, phòng, giảng viên',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: c.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Xóa tìm kiếm',
                                  onPressed: () {
                                    _search.clear();
                                    c.search('');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final filter in ScheduleFilter.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(switch (filter) {
                                    ScheduleFilter.all => 'Tất cả',
                                    ScheduleFilter.classes => 'Lịch học',
                                    ScheduleFilter.exams => 'Lịch thi',
                                  }),
                                  selected: c.filter == filter,
                                  onSelected: (_) => c.selectFilter(filter),
                                ),
                              ),
                            const SizedBox(width: 4),
                            FilterChip(
                              label: const Text('Cả tuần'),
                              avatar: const Icon(
                                Icons.view_week_outlined,
                                size: 17,
                              ),
                              selected: c.weekOverview,
                              onSelected: c.showWeek,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(
                            '${entries.length} buổi ${c.weekOverview ? 'trong tuần' : 'trong ngày'}',
                            style: t.labelLarge,
                          ),
                          if (c.updatedAt != null)
                            Text(
                              'Cập nhật ${TimeOfDay.fromDateTime(c.updatedAt!).format(context)}',
                              style: t.bodySmall?.copyWith(
                                color: s.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      if (c.loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            label: 'Đang cập nhật lịch học',
                            child: const LinearProgressIndicator(minHeight: 3),
                          ),
                        ),
                      if (c.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Card(
                            color: s.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.error!,
                                    style: TextStyle(color: s.onErrorContainer),
                                  ),
                                  if (c.updatedAt != null)
                                    const Text(
                                      'Đang hiển thị lịch đã tải trước đó.',
                                    ),
                                  TextButton.icon(
                                    onPressed: c.loading ? null : c.refresh,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Thử lại'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty && !c.loading && c.error == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
                child: Column(
                  children: [
                    Icon(
                      c.query.isNotEmpty || c.filter != ScheduleFilter.all
                          ? Icons.search_off_rounded
                          : Icons.event_available_rounded,
                      size: 46,
                      color: s.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      c.query.isNotEmpty || c.filter != ScheduleFilter.all
                          ? 'Chưa tìm thấy buổi học'
                          : 'Bạn đang có một khoảng nghỉ',
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Thử ngày khác, xem cả tuần hoặc kéo xuống để cập nhật.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: s.onSurfaceVariant),
                    ),
                    if (c.query.isNotEmpty || c.filter != ScheduleFilter.all)
                      TextButton(
                        onPressed: _clear,
                        child: const Text('Xóa bộ lọc'),
                      ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final entry = entries[index];
                final dateHeader =
                    c.weekOverview &&
                    (index == 0 ||
                        !sameDay(entries[index - 1].date, entry.date));
                return Column(
                  key: ValueKey(
                    '${entry.id}-${entry.dateText}-${entry.startTime}',
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dateHeader)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 12),
                        child: Text(
                          dayTitle(entry.date),
                          style: t.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Reveal(
                      child: EntryCard(
                        entry: entry,
                        compact: widget.compact,
                        now: c.now,
                        onTap: () => c.openCheckIn(entry),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              }, childCount: entries.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayOverview extends StatelessWidget {
  const _DayOverview({required this.controller});
  final ScheduleController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final entries = c.dayEntries;
    final today = sameDay(c.selectedDay, c.now);
    final live = today ? currentClass(entries, c.now) : null;
    final future = entries
        .where((e) => !today || e.endMinutes > minuteOfDay(c.now))
        .toList();
    final focus = live ?? (future.isNotEmpty ? future.first : null);
    final label = c.loading && entries.isEmpty
        ? 'ĐANG CẬP NHẬT'
        : live != null
        ? (minuteOfDay(c.now) < live.startMinutes
              ? 'SẮP BẮT ĐẦU'
              : 'BUỔI HỌC HIỆN TẠI')
        : today
        ? 'HÔM NAY CỦA BẠN'
        : 'LỊCH CỦA BẠN';
    final finished = entries
        .where(
          (e) =>
              e.date.isBefore(dateOnly(c.now)) ||
              (today && e.endMinutes <= minuteOfDay(c.now)),
        )
        .length;
    return CampusSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                color: CampusColors.cyan,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: CampusColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (focus != null)
                IconButton(
                  onPressed: () => c.openCheckIn(focus),
                  tooltip: 'Chi tiết buổi nổi bật',
                  color: Colors.white,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: const Icon(Icons.arrow_outward_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            c.loading && entries.isEmpty
                ? 'Đang lấy lịch học…'
                : c.error != null && c.updatedAt == null
                ? 'Lịch học chưa sẵn sàng'
                : focus?.subjectLabel ??
                      (entries.isEmpty
                          ? 'Một ngày nhẹ nhàng'
                          : 'Đã hoàn tất lịch hôm nay'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            focus == null
                ? (c.error != null
                      ? 'Kéo xuống để thử cập nhật lại lịch học.'
                      : 'Chủ động thời gian cho những điều quan trọng.')
                : '${focus.timeRange} · ${focus.roomLabel}',
            style: const TextStyle(color: Color(0xFFE1ECFF)),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CampusGlassStat(
                icon: Icons.layers_outlined,
                label: '${entries.length} buổi',
              ),
              if (entries.any((e) => e.periodCount > 0))
                CampusGlassStat(
                  color: CampusColors.mint,
                  icon: Icons.schedule_rounded,
                  label:
                      '${entries.fold<int>(0, (sum, e) => sum + e.periodCount)} tiết',
                ),
              if (entries.any((e) => e.isExam))
                CampusGlassStat(
                  color: CampusColors.gold,
                  icon: Icons.edit_calendar_outlined,
                  label: '${entries.where((e) => e.isExam).length} lịch thi',
                ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: finished / entries.length,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
              color: CampusColors.cyan,
              backgroundColor: Colors.white.withValues(alpha: .10),
            ),
            const SizedBox(height: 7),
            Text(
              'Đã kết thúc $finished/${entries.length} buổi',
              style: const TextStyle(color: Color(0xFFBBD9E7), fontSize: 11),
            ),
          ],
          if (focus != null && live != null && !focus.isPresent) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: CampusColors.navy,
              ),
              onPressed: () => c.openCheckIn(focus),
              icon: const Icon(Icons.how_to_reg_outlined, size: 18),
              label: const Text('Điểm danh buổi học'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Chữ lớn cần toàn bộ chiều ngang; nhãn thống kê chuyển xuống dưới tiêu đề.
class _ScheduleHeading extends StatelessWidget {
  const _ScheduleHeading({required this.lessonCount});
  final int lessonCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KẾ HOẠCH CÁ NHÂN',
          style: text.labelSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Lịch học',
          style: text.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
          ),
        ),
      ],
    );
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$lessonCount buổi / tuần',
        style: text.labelSmall?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), badge],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            badge,
          ],
        );
      },
    );
  }
}
