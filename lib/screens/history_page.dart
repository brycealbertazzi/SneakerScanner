import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/enums.dart';
import '../models/scan_data.dart';
import 'demo/demo_controller.dart';
import 'main_screen.dart';
import 'scan_detail/scan_detail_page.dart';
import '../theme/app_theme.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateFilter _dateFilter = DateFilter.all;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  /// Stored once so StreamBuilder always receives the same stream object,
  /// preventing re-subscription (and the loading spinner) on every setState.
  late final Stream<DatabaseEvent> _scansStream;

  DatabaseReference get _scansRef {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseDatabase.instance
        .ref()
        .child('scans')
        .child(user?.uid ?? '');
  }

  @override
  void initState() {
    super.initState();
    _scansStream = _scansRef.orderByChild('timestamp').onValue;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<String, dynamic>> _filterScans(
    List<MapEntry<String, dynamic>> scans,
  ) {
    return scans.where((entry) {
      final data = Map<String, dynamic>.from(entry.value);
      final scanData = ScanData.fromFirebase(data);
      final code = (scanData.sku ?? '').toLowerCase();
      final productTitle = (data['productTitle'] ?? '')
          .toString()
          .toLowerCase();
      final timestamp = data['timestamp'] as int?;

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!code.contains(query) && !productTitle.contains(query)) {
          return false;
        }
      }

      if (timestamp != null && _dateFilter != DateFilter.all) {
        final scanDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        switch (_dateFilter) {
          case DateFilter.today:
            final scanDay = DateTime(
              scanDate.year,
              scanDate.month,
              scanDate.day,
            );
            if (scanDay != today) return false;
            break;
          case DateFilter.week:
            final weekAgo = today.subtract(const Duration(days: 7));
            if (scanDate.isBefore(weekAgo)) return false;
            break;
          case DateFilter.month:
            final monthAgo = today.subtract(const Duration(days: 30));
            if (scanDate.isBefore(monthAgo)) return false;
            break;
          case DateFilter.custom:
            if (_customStartDate != null &&
                scanDate.isBefore(_customStartDate!)) {
              return false;
            }
            if (_customEndDate != null) {
              final endOfDay = DateTime(
                _customEndDate!.year,
                _customEndDate!.month,
                _customEndDate!.day,
                23,
                59,
                59,
              );
              if (scanDate.isAfter(endOfDay)) return false;
            }
            break;
          case DateFilter.all:
            break;
        }
      }

      return true;
    }).toList();
  }

  Map<String, List<MapEntry<String, dynamic>>> _groupByDate(
    List<MapEntry<String, dynamic>> scans,
  ) {
    final Map<String, List<MapEntry<String, dynamic>>> grouped = {};

    for (final entry in scans) {
      final scanData = Map<String, dynamic>.from(entry.value);
      final timestamp = scanData['timestamp'] as int?;
      final dateKey = timestamp != null ? _getDateKey(timestamp) : 'Unknown';

      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(entry);
    }

    return grouped;
  }

  String _getDateKey(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scanDay = DateTime(date.year, date.month, date.day);

    if (scanDay == today) {
      return 'Today';
    } else if (scanDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (scanDay.isAfter(today.subtract(const Duration(days: 7)))) {
      final weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return weekdays[date.weekday - 1];
    } else {
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  Future<void> _showDateRangePicker() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _dateFilter = DateFilter.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        // Horizontal padding lives on each child rather than here so the chip
        // row and list can draw card shadows without being clipped.
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: AppColors.cardShadow,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by product name or code...',
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.textSecondary,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    _buildFilterChip('All', DateFilter.all),
                    const SizedBox(width: 8),
                    _buildFilterChip('Today', DateFilter.today),
                    const SizedBox(width: 8),
                    _buildFilterChip('This Week', DateFilter.week),
                    const SizedBox(width: 8),
                    _buildFilterChip('This Month', DateFilter.month),
                    const SizedBox(width: 8),
                    _buildCustomDateChip(),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              Expanded(
                child: StreamBuilder<DatabaseEvent>(
                  stream: _scansStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading scans',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      );
                    }

                    final data = snapshot.data?.snapshot.value;
                    if (data == null) {
                      return _buildEmptyState();
                    }

                    final scansMap = Map<String, dynamic>.from(data as Map);
                    var scansList = scansMap.entries.toList();
                    scansList.sort((a, b) {
                      final aTime = (a.value['timestamp'] ?? 0) as int;
                      final bTime = (b.value['timestamp'] ?? 0) as int;
                      return bTime.compareTo(aTime);
                    });

                    final filteredScans = _filterScans(scansList);

                    if (filteredScans.isEmpty) {
                      return _buildNoResultsState();
                    }

                    final groupedScans = _groupByDate(filteredScans);
                    final dateKeys = groupedScans.keys.toList();

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      itemCount: dateKeys.length,
                      itemBuilder: (context, sectionIndex) {
                        final dateKey = dateKeys[sectionIndex];
                        final scansInSection = groupedScans[dateKey]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sectionIndex > 0) const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 10,
                              ),
                              child: Text(
                                dateKey,
                                style: GoogleFonts.inter(
                                  letterSpacing: -0.5,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            ...scansInSection.asMap().entries.map((entry) {
                              final index = entry.key;
                              final scanEntry = entry.value;
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: index < scansInSection.length - 1
                                      ? 8
                                      : 0,
                                ),
                                child: _buildScanCard(scanEntry),
                              );
                            }),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, DateFilter filter) {
    final isSelected = _dateFilter == filter;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _dateFilter = filter),
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.black.withValues(alpha: 0.08),
        highlightColor: Colors.black.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.textPrimary : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.buttonBorder,
            ),
            boxShadow: isSelected ? null : AppColors.buttonShadow(),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDateChip() {
    final isSelected = _dateFilter == DateFilter.custom;
    String label = 'Custom';
    if (isSelected && _customStartDate != null && _customEndDate != null) {
      final start = '${_customStartDate!.month}/${_customStartDate!.day}';
      final end = '${_customEndDate!.month}/${_customEndDate!.day}';
      label = '$start - $end';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showDateRangePicker,
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.black.withValues(alpha: 0.08),
        highlightColor: Colors.black.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.textPrimary : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.buttonBorder,
            ),
            boxShadow: isSelected ? null : AppColors.buttonShadow(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today,
                size: 14,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        key: DemoKeys.key(DemoTarget.historyEmptyState),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.cardShadow,
            ),
            child: Icon(
              Icons.qr_code_scanner,
              size: 40,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No scans yet',
            style: GoogleFonts.inter(
              letterSpacing: -0.5,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a label to see it here',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.cardShadow,
            ),
            child: Icon(
              Icons.search_off,
              size: 40,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No results found',
            style: GoogleFonts.inter(
              letterSpacing: -0.5,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _dateFilter = DateFilter.all;
                _customStartDate = null;
                _customEndDate = null;
              });
            },
            child: Text(
              'Clear all filters',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard(MapEntry<String, dynamic> entry) {
    final data = Map<String, dynamic>.from(entry.value);
    final scanData = ScanData.fromFirebase(data);
    final productTitle = data['productTitle'] as String?;
    final productImage = data['productImage'] as String?;
    final timestamp = data['timestamp'] as int?;
    final timeStr = timestamp != null ? _formatTime(timestamp) : '';

    final displayTitle = productTitle != null && productTitle.isNotEmpty
        ? productTitle
        : scanData.displayName.isNotEmpty
        ? scanData.displayName
        : 'Unknown Product';
    final hasProductInfo = productTitle != null && productTitle.isNotEmpty;
    final hasImage = productImage != null && productImage.isNotEmpty;

    final subtitle = scanData.sku ?? '';
    final isStyleCode = scanData.sku != null;

    return Dismissible(
      key: Key(entry.key),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        _scansRef.child(entry.key).remove();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () async {
          final mainScreenState = context
              .findAncestorStateOfType<MainScreenState>();

          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ScanDetailPage(
                scanId: entry.key,
                scanData: scanData,
                timestamp: timestamp ?? 0,
              ),
            ),
          );

          if (result == 'scanAnother') {
            mainScreenState?.switchToTab(0);
          }
        },
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: hasImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          productImage,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.directions_run,
                            color: AppColors.textPrimary,
                            size: 26,
                          ),
                        ),
                      )
                    : Icon(
                        hasProductInfo
                            ? Icons.directions_run
                            : Icons.help_outline_rounded,
                        color: hasProductInfo
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        size: 26,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: hasProductInfo
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          isStyleCode ? Icons.label : Icons.qr_code,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle,
                            style: GoogleFonts.robotoMono(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.textPrimary,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
}
