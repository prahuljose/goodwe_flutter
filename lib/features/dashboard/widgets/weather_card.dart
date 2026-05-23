import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../data/models/station_monitor.dart';

class WeatherSection extends StatelessWidget {
  final List<WeatherForecast> forecast;

  const WeatherSection({super.key, required this.forecast});

  @override
  Widget build(BuildContext context) {
    if (forecast.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: '7-Day Forecast'),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: forecast.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _WeatherDayCard(day: forecast[i], isToday: i == 0),
          ),
        ),
      ],
    );
  }
}

class _WeatherDayCard extends StatelessWidget {
  final WeatherForecast day;
  final bool isToday;

  const _WeatherDayCard({required this.day, required this.isToday});

  String get _dayLabel {
    if (isToday) return 'Today';
    try {
      final date = DateTime.parse(day.date);
      return DateFormat('EEE').format(date);
    } catch (_) {
      return day.date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isToday ? AppColors.accent.withValues(alpha: 0.15) : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday ? AppColors.accent.withValues(alpha: 0.4) : AppColors.divider,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _dayLabel,
            style: TextStyle(
              color: isToday ? AppColors.accent : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(day.weatherIcon, style: const TextStyle(fontSize: 24)),
          Column(
            children: [
              Text(
                '${day.tmpMax}°',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${day.tmpMin}°',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.water_drop_outlined, size: 10, color: Color(0xFF60A5FA)),
              const SizedBox(width: 2),
              Text(
                '${day.pop}%',
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
