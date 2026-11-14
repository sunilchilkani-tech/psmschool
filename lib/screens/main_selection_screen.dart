import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialogs.dart';
import '../widgets/global_student_search_card.dart';
import 'professional_management_hub.dart';

class MainSelectionScreen extends StatelessWidget {
  const MainSelectionScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      emoji: '\u{1F6AA}',
      message: '\u0AB2\u0AC9\u0A97 \u0A86\u0A89\u0A9F \u0A95\u0AB0\u0AB5\u0ABE \u0AAE\u0ABE\u0A82\u0A97\u0ACB \u0A9B\u0ACB?',
      yesLabel: '\u0AB9\u0ABE, \u0AB2\u0AC9\u0A97 \u0A86\u0A89\u0A9F',
      noLabel: '\u0AA8\u0ABE',
    );
    if (ok && context.mounted) {
      await context.read<AppState>().logout();
    }
  }

  Future<void> _configureResultUrl(BuildContext context) async {
    showSnack(context, 'હાજરી અને પરિણામનું ડેટા Supabase માં છે. Web App URL સેટ કરવાની જરૂર નથી.');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final teacherName = state.currentTeacher?.name ?? '';

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: DecoratedBox(decoration: AppTheme.backgroundGradient)),
          Column(
            children: [
              Container(
                width: double.infinity,
                decoration: AppTheme.headerGradient,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '\u{1F464} $teacherName',
                                style: guFont(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.goldLight,
                                ),
                              ),
                            ),
                            if (state.isAdmin)
                              IconButton(
                                tooltip: 'School / API Settings',
                                onPressed: () => _configureResultUrl(context),
                                icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
                              ),
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _confirmLogout(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '\u{1F6AA} \u0AB2\u0AC9\u0A97 \u0A86\u0A89\u0A9F',
                                  style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (state.logoUrl.isNotEmpty)
                        Image.network(state.logoUrl, height: 64, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_rounded, size: 60, color: Colors.white))
                      else
                        const Icon(Icons.account_balance_rounded, size: 60, color: Colors.white),
                      const SizedBox(height: 10),
                      Text(
                        state.schoolName,
                        textAlign: TextAlign.center,
                        style: guFont(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      Text(
                        '\u0AAE\u0AC1\u0A96\u0ACD\u0AAF \u0AAE\u0AC7\u0AA8\u0AC1',
                        textAlign: TextAlign.center,
                        style: guFont(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.goldLight),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const GlobalStudentSearchCard(),
                          const SizedBox(height: 8),
                          _moduleCard(
                            emoji: '\u{1F4DD}',
                            // "હાજરી"
                            title: '\u0AB9\u0ABE\u0A9C\u0AB0\u0AC0',
                            // "દૈનિક હાજરી નોંધણી, પીએમ પોષણ, અલ્પાહાર અને માસિક રિપોર્ટ"
                            subtitle:
                                '\u0AA6\u0AC8\u0AA8\u0ABF\u0A95 \u0AB9\u0ABE\u0A9C\u0AB0\u0AC0 \u0AA8\u0ACB\u0A82\u0AA7\u0AA3\u0AC0, \u0AAA\u0AC0\u0A8F\u0AAE \u0AAA\u0ACB\u0AB7\u0AA3, \u0A85\u0AB2\u0ACD\u0AAA\u0ABE\u0AB9\u0ABE\u0AB0 \u0A85\u0AA8\u0AC7 \u0AAE\u0ABE\u0AB8\u0ABF\u0A95 \u0AB0\u0ABF\u0AAA\u0ACB\u0AB0\u0ACD\u0A9F',
                            accentColor: AppColors.navyMid,
                            onTap: () => state.setActiveModule('attendance'),
                          ),
                          // PM POSHAN યુઝરને પરિણામ અને અપલોડ બટન ન દેખાય તે માટેનું ફિલ્ટર
                          if (teacherName.trim().toUpperCase() != 'PM POSHAN') ...[
                            const SizedBox(height: 16),
                            _moduleCard(
                              emoji: '📊', 
                              title: 'પરિણામ પત્રક',
                              subtitle: 'સત્ર-૧, સત્ર-૨ અને વાર્ષિક વિષયવાર ગુણ એન્ટ્રી અને PDF પરિણામ પત્રક',
                              accentColor: AppColors.greenDeep,
                              onTap: () => state.setActiveModule('result'),
                            ),
                            const SizedBox(height: 16),
                            _moduleCard(
                              emoji: '🛠️',
                              title: 'વ્યવસાયિક વ્યવસ્થાપન (Supabase)',
                              subtitle: 'વિદ્યાર્થી ઉમેરો/સુધારો, રોલ નંબર, શિક્ષક/વર્ગ વ્યવસ્થાપન, Excel import/export અને report preferences',
                              accentColor: Colors.orange,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const ProfessionalManagementHub()),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moduleCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 32)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: guFont(fontSize: 22, fontWeight: FontWeight.w900, color: accentColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: guFont(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: accentColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}