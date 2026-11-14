import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/school_name_language_selector.dart';
import '../widgets/global_student_search_card.dart';
import 'datewise_panel.dart';
import 'entry_panel.dart';
import 'history_panel.dart';
import 'summary_panel.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;
  bool _checkedMessage = false;

  static const _tabs = ['📝 હાજરી નોંધણી', '📋 ઇતિહાસ જુઓ', '📊 દૈનિક રિપોર્ટ', '📄 DATE WISE PDF'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedMessage) {
      _checkedMessage = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkTodayMessage());
    }
  }

  Future<void> _checkTodayMessage() async {
    final state = context.read<AppState>();
    final api = state.api;
    final teacher = state.currentTeacher;
    if (api == null || teacher == null) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // ૧. એડમિન મેસેજ ચેક કરો
    if (!state.isMessageRead(teacher.name, today)) {
      try {
        final msg = await api.getTodayMessage(today);
        if (!mounted) return;
        if (msg.trim().isNotEmpty) {
          await showTeacherMessageDialog(context, msg.trim());
          await state.markMessageRead(teacher.name, today);
        }
      } catch (_) {}
    }

    // ૨. વિદ્યાર્થીઓના બર્થડે મેસેજ ચેક કરો (આજે અને આવતીકાલ)
    if (!state.isMessageRead('${teacher.name}_student_bday', today)) {
      try {
        // શિક્ષકના પોતાના જ ક્લાસ પાસ થશે
        final studentBdayMsg = await api.getStudentBirthdays(teacher.classes ?? []);
        if (!mounted) return;
        if (studentBdayMsg.trim().isNotEmpty) {
          await showTeacherMessageDialog(context, studentBdayMsg.trim());
          await state.markMessageRead('${teacher.name}_student_bday', today);
        }
      } catch (_) {}
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showConfirmDialog(
      context,
      emoji: '🚪',
      message: 'લૉગ આઉટ કરવા માંગો છો?',
      yesLabel: 'હા, લૉગ આઉટ',
      noLabel: 'ના',
    );
    if (ok && mounted) {
      await context.read<AppState>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final teacher = appState.currentTeacher;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: DecoratedBox(decoration: AppTheme.backgroundGradient)),
          Column(
            children: [
              _buildHeader(teacher?.name ?? ''),
              _buildTabs(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const GlobalStudentSearchCard(),
                          const [
                            EntryPanel(),
                            HistoryPanel(),
                            SummaryPanel(),
                            DateWisePanel(),
                          ][_tabIndex],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Watermark - centered, low opacity, never intercepts taps.
          if (appState.logoUrl.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: 0.07,
                    child: SizedBox(width: 300, child: Image.network(appState.logoUrl, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(String teacherName) {
    final schoolState = context.watch<AppState>();
    return Container(
      width: double.infinity,
      decoration: AppTheme.headerGradient,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.read<AppState>().setActiveModule('menu'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '\u{2B05}\u{FE0F} \u0AAE\u0AC1\u0A96\u0ACD\u0AAF \u0AAE\u0AC7\u0AA8\u0AC1',
                        style: guFont(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '\u{1F464} $teacherName',
                      overflow: TextOverflow.ellipsis,
                      style: guFont(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.goldLight),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => showGlobalStudentSearchDialog(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('🔍 વિદ્યાર્થી સર્ચ', style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _confirmLogout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('🚪 લૉગ આઉટ', style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.18),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                schoolState.schoolName,
                style: guFont(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.goldLight, letterSpacing: 1.2),
              ),
            ),
            const SizedBox(height: 12),
            Text(schoolState.schoolName,
                textAlign: TextAlign.center,
                style: guFont(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            SchoolNameLanguageSelector(
              schoolRef: schoolState.schoolNameLanguageRef,
              label: 'School name language / શાળાના નામની ભાષા',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text('હાજરી વ્યવસ્થાપન',
                textAlign: TextAlign.center,
                style: guFont(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.goldLight)),
            const SizedBox(height: 8),
            Text(
              'ડેટા સીધા Google Sheet માં સાચવવામાં આવે છે',
              style: guFont(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.65)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [AppTheme.shadowSm],
            ),
            child: Wrap(
              children: List.generate(_tabs.length, (i) {
                final active = i == _tabIndex;
                return _TabButton(
                  label: _tabs[i],
                  active: active,
                  onTap: () => setState(() => _tabIndex = i),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: active ? AppColors.navy : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: guFont(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.slate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}