import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors_redesign.dart';
import '../../core/theme/app_typography_redesign.dart';
import '../../core/theme/app_spacing_redesign.dart';
import '../../core/theme/redesign_components.dart';

/// Home Screen Redesigned - "วันนี้" (Today)
///
/// Design Changes:
/// - Warm gradient hero section
/// - Prominent streak display
/// - Clear visual hierarchy
/// - Natural, human-centered feel
class HomeScreenRedesign extends StatelessWidget {
  const HomeScreenRedesign({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: AppColorsRedesign.getSurfaceColor(brightness, 0),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Hero Section with Gradient
              SliverToBoxAdapter(
                child: _HeroSection(),
              ),

              // Continue Learning Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: AppSpacing.screenPaddingAll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'เรียนต่อจากเดิม',
                        style: AppTypographyRedesign.display3(context),
                      ),
                      SizedBox(height: AppSpacing.marginMd),
                      _ContinueLearningCard(),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(child: AppSpacing.sectionGapBox),

              // Review Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: AppSpacing.screenPaddingAll,
                  child: _ReviewSection(),
                ),
              ),

              SliverToBoxAdapter(child: AppSpacing.sectionGapBox),

              // Daily Goal Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: AppSpacing.screenPaddingAll,
                  child: _DailyGoalSection(),
                ),
              ),

              SliverToBoxAdapter(child: AppSpacing.sectionGapBox),

              // Quick Actions
              SliverToBoxAdapter(
                child: Padding(
                  padding: AppSpacing.screenPaddingAll,
                  child: _QuickActionsSection(),
                ),
              ),

              // Bottom padding
              SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.space16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero Section - Gradient background with streak
class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      decoration: BoxDecoration(
        gradient: brightness == Brightness.light
            ? AppColorsRedesign.heroGradientLight
            : AppColorsRedesign.heroGradientDark,
      ),
      padding: EdgeInsets.all(AppSpacing.paddingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Text(
            'สวัสดี! 👋',
            style: AppTypographyRedesign.display2(context).copyWith(
              color: AppColorsRedesign.getTextColor(brightness),
            ),
          ),
          SizedBox(height: AppSpacing.space2),

          // Motivational message
          Text(
            'พร้อมเรียนรู้คำศัพท์ใหม่กันเถอะ',
            style: AppTypographyRedesign.bodyLarge(context).copyWith(
              color: AppColorsRedesign.getTextColor(brightness, secondary: true),
            ),
          ),

          SizedBox(height: AppSpacing.marginLg),

          // Streak Display - Large and prominent
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingLg,
                  vertical: AppSpacing.paddingMd,
                ),
                decoration: BoxDecoration(
                  color: AppColorsRedesign.streakFire.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(
                    color: AppColorsRedesign.streakFire.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: StreakDisplay(
                  streakCount: 7,
                  isLarge: true,
                ),
              ),
            ],
          ),

          SizedBox(height: AppSpacing.marginMd),

          // Daily Progress
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ความคืบหน้าวันนี้',
                    style: AppTypographyRedesign.bodySmall(context).copyWith(
                      color: AppColorsRedesign.getTextColor(brightness, secondary: true),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '3/5 คำ',
                    style: AppTypographyRedesign.bodySmall(context).copyWith(
                      color: AppColorsRedesign.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.space2),
              ModernProgressBar(
                progress: 0.6,
                height: AppSpacing.progressBarHeightLarge,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Continue Learning Card - Large, clear CTA
class _ContinueLearningCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ModernCard(
      elevation: 2,
      onTap: () {
        // Navigate to lesson
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category badge
          Row(
            children: [
              ModernChip(
                label: 'บทเรียนที่ 1',
                icon: Icons.school_outlined,
                isSelected: true,
              ),
            ],
          ),

          SizedBox(height: AppSpacing.marginMd),

          // Word preview
          Container(
            padding: EdgeInsets.all(AppSpacing.paddingMd),
            decoration: BoxDecoration(
              color: AppColorsRedesign.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                // Word
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'station',
                        style: AppTypographyRedesign.vocabularyWord(context).copyWith(
                          fontSize: 28,
                        ),
                      ),
                      SizedBox(height: AppSpacing.space1),
                      Text(
                        'สถานี',
                        style: AppTypographyRedesign.bodyLarge(context).copyWith(
                          color: AppColorsRedesign.getTextColor(
                            Theme.of(context).brightness,
                            secondary: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Play audio button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColorsRedesign.primary,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.sm,
                  ),
                  child: Icon(
                    Icons.volume_up_rounded,
                    color: Colors.white,
                    size: AppSpacing.iconMd,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: AppSpacing.marginMd),

          // Context
          Text(
            'คำจากบทวาม',
            style: AppTypographyRedesign.bodySmall(context).copyWith(
              color: AppColorsRedesign.getTextColor(
                Theme.of(context).brightness,
                secondary: true,
              ),
            ),
          ),
          Text(
            'เคยตอบผิด',
            style: AppTypographyRedesign.bodySmall(context).copyWith(
              color: AppColorsRedesign.warning,
              fontWeight: FontWeight.w600,
            ),
          ),

          SizedBox(height: AppSpacing.marginLg),

          // CTA Button
          ModernPrimaryButton(
            label: 'เรียนต่อ',
            icon: Icons.play_arrow_rounded,
            onPressed: () {},
            size: ButtonSize.large,
          ),
        ],
      ),
    );
  }
}

/// Review Section
class _ReviewSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ModernCard(
      child: Row(
        children: [
          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColorsRedesign.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              Icons.refresh_rounded,
              color: AppColorsRedesign.warning,
              size: AppSpacing.iconLg,
            ),
          ),

          SizedBox(width: AppSpacing.marginMd),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'รายการทบทวน 1 คำ',
                  style: AppTypographyRedesign.bodyLarge(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: AppSpacing.space1),
                Text(
                  'ทบทวนคำที่ควรฝึกซ้ำ',
                  style: AppTypographyRedesign.bodySmall(context).copyWith(
                    color: AppColorsRedesign.getTextColor(
                      Theme.of(context).brightness,
                      secondary: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Arrow
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: AppSpacing.iconSm,
            color: AppColorsRedesign.getTextColor(
              Theme.of(context).brightness,
              tertiary: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Daily Goal Section
class _DailyGoalSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_rounded,
                color: AppColorsRedesign.primary,
                size: AppSpacing.iconMd,
              ),
              SizedBox(width: AppSpacing.space2),
              Text(
                'เป้าหมายของฉัน',
                style: AppTypographyRedesign.display3(context).copyWith(
                  fontSize: 18,
                ),
              ),
            ],
          ),

          SizedBox(height: AppSpacing.marginMd),

          Text(
            'ตั้งเป้าหมายเล็ก ๆ ที่ทำได้ทุกวัน',
            style: AppTypographyRedesign.bodyMedium(context).copyWith(
              color: AppColorsRedesign.getTextColor(
                Theme.of(context).brightness,
                secondary: true,
              ),
            ),
          ),

          SizedBox(height: AppSpacing.marginLg),

          ModernPrimaryButton(
            label: 'จัดการเป้าหมาย',
            icon: Icons.tune_rounded,
            onPressed: () {},
            size: ButtonSize.medium,
          ),
        ],
      ),
    );
  }
}

/// Quick Actions Section
class _QuickActionsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'เมนูเพิ่มเติม',
          style: AppTypographyRedesign.display3(context).copyWith(
            fontSize: 18,
          ),
        ),
        SizedBox(height: AppSpacing.marginMd),

        Wrap(
          spacing: AppSpacing.marginMd,
          runSpacing: AppSpacing.marginMd,
          children: [
            ModernChip(
              label: 'เลือกฝึกเอง',
              icon: Icons.grid_view_rounded,
              onTap: () {},
            ),
            ModernChip(
              label: 'ประวัติการเรียน',
              icon: Icons.history_rounded,
              onTap: () {},
            ),
            ModernChip(
              label: 'สถิติ',
              icon: Icons.bar_chart_rounded,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}
