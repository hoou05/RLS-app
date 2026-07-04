import 'package:flutter/material.dart';

void main() {
  runApp(const RlsScreeningApp());
}

const forest = Color(0xff123c2c);
const leaf = Color(0xff168342);
const mint = Color(0xffeaf8f0);
const softMint = Color(0xfff7fcf8);

class RlsScreeningApp extends StatelessWidget {
  const RlsScreeningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RLS Screen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: leaf,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: mint,
        useMaterial3: true,
      ),
      home: const ShellPage(),
    );
  }
}

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int index = 0;
  final healthService = MockHealthDataService();
  String result = 'No screening result yet.';

  @override
  Widget build(BuildContext context) {
    final pages = [
      LoginRegisterPage(onDemoLogin: () => setState(() => index = 1)),
      const ConsentPage(),
      HealthPermissionPage(service: healthService),
      HomeDashboardPage(
        result: result,
        onPredict: () => setState(() => result = 'Moderate risk estimate - fallback MVP model'),
      ),
      const QuestionnairePage(),
      RiskResultPage(result: result),
      const SleepAgentPage(),
      const HistoryPage(),
    ];
    return Scaffold(
      body: AnimatedScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              const MobileHeader(),
              Expanded(child: pages[index]),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => index = 6),
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Agent'),
        backgroundColor: leaf,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        indicatorColor: const Color(0xffdff3e8),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.login), label: 'Login'),
          NavigationDestination(icon: Icon(Icons.verified_user), label: 'Consent'),
          NavigationDestination(icon: Icon(Icons.health_and_safety), label: 'Health'),
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Survey'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Result'),
          NavigationDestination(icon: Icon(Icons.smart_toy), label: 'Agent'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

class ApiClient {
  ApiClient({this.baseUrl = 'http://localhost:8000'});
  final String baseUrl;
  String? token;

  // TODO: wire register/login/upload/questionnaire/prediction calls to FastAPI.
}

abstract class HealthDataService {
  Future<bool> requestPermissions();
  Future<List<Map<String, dynamic>>> fetchSleepData();
  Future<List<Map<String, dynamic>>> fetchHeartRateData();
  Future<List<Map<String, dynamic>>> fetchStepsData();
  Future<void> syncToBackend(ApiClient client);
}

class MockHealthDataService implements HealthDataService {
  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<List<Map<String, dynamic>>> fetchSleepData() async => [
        {'duration_minutes': 405, 'sleep_efficiency': 80}
      ];

  @override
  Future<List<Map<String, dynamic>>> fetchHeartRateData() async => [
        {'bpm': 78, 'resting_bpm': 69}
      ];

  @override
  Future<List<Map<String, dynamic>>> fetchStepsData() async => [
        {'count': 5200}
      ];

  @override
  Future<void> syncToBackend(ApiClient client) async {
    // TODO: replace with Flutter health package reads from Apple HealthKit and Android Health Connect.
    // Keep permission requests, background sync, and backend upload behind this interface.
  }
}

class AnimatedScreenBackground extends StatefulWidget {
  const AnimatedScreenBackground({super.key, required this.child});
  final Widget child;

  @override
  State<AnimatedScreenBackground> createState() => _AnimatedScreenBackgroundState();
}

class _AnimatedScreenBackgroundState extends State<AnimatedScreenBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final shift = 18 * controller.value;
        return Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [softMint, mint, Color(0xffe3f3ea)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              top: 88 - shift,
              right: -130 + shift,
              child: const MotionRing(width: 340, height: 120),
            ),
            Positioned(
              bottom: 130 + shift,
              left: -120,
              child: const MotionRing(width: 300, height: 110),
            ),
            Positioned(
              top: 280 + shift,
              left: 80,
              child: const MotionRing(width: 260, height: 92),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}

class MotionRing extends StatelessWidget {
  const MotionRing({super.key, required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.16,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: leaf.withOpacity(0.18), width: 1.4),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class MobileHeader extends StatelessWidget {
  const MobileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          const RlsLogoMark(size: 42),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RLS Screen', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text('Rest-aware screening MVP', style: TextStyle(color: Color(0xff557466), fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xffe5f4ee),
              border: Border.all(color: const Color(0xffb8dfce)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Mock data', style: TextStyle(color: Color(0xff145a49), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class RlsLogoMark extends StatelessWidget {
  const RlsLogoMark({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xff1ca45b), Color(0xff0f6d42)]),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: leaf.withOpacity(0.22), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.monitor_heart, color: Colors.white, size: 23),
          Positioned(
            right: 8,
            bottom: 7,
            child: Transform.rotate(
              angle: -0.24,
              child: Container(
                width: 22,
                height: 13,
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Colors.white, width: 3),
                    bottom: BorderSide(color: Colors.white, width: 3),
                  ),
                  borderRadius: BorderRadius.only(bottomRight: Radius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginRegisterPage extends StatelessWidget {
  const LoginRegisterPage({super.key, required this.onDemoLogin});
  final VoidCallback onDemoLogin;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Create or sign in',
        subtitle: 'Use a demo account to test the local MVP flow.',
        child: Column(
          children: [
            const TextField(decoration: InputDecoration(labelText: 'Email', filled: true)),
            const SizedBox(height: 12),
            const TextField(decoration: InputDecoration(labelText: 'Password', filled: true), obscureText: true),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onDemoLogin,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue demo'),
              ),
            ),
          ],
        ),
      );
}

class ConsentPage extends StatelessWidget {
  const ConsentPage({super.key});

  @override
  Widget build(BuildContext context) => const PageFrame(
        title: 'Consent note',
        subtitle: 'MVP consent is intentionally lightweight for local testing.',
        child: Text('This MVP collects wearable and questionnaire data for non-diagnostic screening research workflows.'),
      );
}

class HealthPermissionPage extends StatelessWidget {
  const HealthPermissionPage({super.key, required this.service});
  final HealthDataService service;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Health data sync',
        subtitle: 'Mock sync today. HealthKit and Health Connect stay behind an interface.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MetricTile(label: 'Sleep', value: '405 min', note: 'mock nightly duration'),
            const MetricTile(label: 'Heart rate', value: '78 bpm', note: 'mock daily mean'),
            const MetricTile(label: 'Steps', value: '5200', note: 'mock movement total'),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: service.requestPermissions,
                icon: const Icon(Icons.sync),
                label: const Text('Request mock permission'),
              ),
            ),
          ],
        ),
      );
}

class HomeDashboardPage extends StatelessWidget {
  const HomeDashboardPage({super.key, required this.result, required this.onPredict});
  final String result;
  final VoidCallback onPredict;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Risk dashboard',
        subtitle: 'Run the fallback model with mock wearable and questionnaire inputs.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [forest, Color(0xff0e6040)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Latest result', style: TextStyle(color: Color(0xffd9f7e5), fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(result, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: result.startsWith('Moderate') ? 0.55 : 0.08,
                      minHeight: 8,
                      backgroundColor: Colors.white24,
                      color: const Color(0xff9af2b7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPredict,
                icon: const Icon(Icons.insights),
                label: const Text('Run demo screening'),
              ),
            ),
          ],
        ),
      );
}

class QuestionnairePage extends StatelessWidget {
  const QuestionnairePage({super.key});

  @override
  Widget build(BuildContext context) => const PageFrame(
        title: 'Questionnaire',
        subtitle: 'Debug scaffold for symptom inputs.',
        child: Text('Fields: urge to move legs, worse at rest, relieved by movement, evening/night pattern, sleep disturbance, frequency, severity.'),
      );
}

class RiskResultPage extends StatelessWidget {
  const RiskResultPage({super.key, required this.result});
  final String result;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Risk result',
        subtitle: 'Screening output for local validation only.',
        child: Text('$result\n\nThis is a screening result, not a diagnosis. Consult a clinician if symptoms persist.'),
      );
}

class SleepAgentPage extends StatefulWidget {
  const SleepAgentPage({super.key});

  @override
  State<SleepAgentPage> createState() => _SleepAgentPageState();
}

class _SleepAgentPageState extends State<SleepAgentPage> {
  final controller = TextEditingController(text: 'Can I take iron or change medication for restless legs?');
  String response = 'Ask a sleep-health question. This local mobile preview uses the same safety posture as the FastAPI agent.';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void answer() {
    final question = controller.text.toLowerCase();
    setState(() {
      if (question.contains('iron') || question.contains('medication') || question.contains('cpap') || question.contains('dose')) {
        response = 'I cannot diagnose, recommend medication or iron, change medication, or adjust CPAP settings. I can help track symptoms and suggest when to contact a clinician or sleep specialist.';
      } else if (question.contains('rls') || question.contains('leg')) {
        response = 'RLS-like education focuses on whether symptoms appear at rest, worsen at night, improve with movement, and affect sleep. This is education only, not a diagnosis.';
      } else {
        response = 'Focus on regular wake time, a stable sleep window, reduced evening caffeine or alcohol, daytime movement, and a quiet cool sleep environment.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Sleep agent',
        subtitle: 'Mobile safety preview for trend education and bounded Q&A.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Question', filled: true),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: answer,
                icon: const Icon(Icons.send),
                label: const Text('Ask local preview'),
              ),
            ),
            const SizedBox(height: 14),
            Text(response, style: const TextStyle(height: 1.45)),
          ],
        ),
      );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => const PageFrame(
        title: 'Debug history',
        subtitle: 'Prediction and questionnaire records will come from FastAPI.',
        child: Text('This screen is for MVP debugging. A patient-facing product would show trends and summaries instead of raw JSON.'),
      );
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, required this.note});
  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffffffff).withOpacity(0.74),
        border: Border.all(color: const Color(0xffd7e8dd)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xff60786b), fontWeight: FontWeight.w800))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              Text(note, style: const TextStyle(color: Color(0xff71877b), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      children: [
        Text(title, style: const TextStyle(fontSize: 30, height: 1.05, fontWeight: FontWeight.w900, color: forest)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: Color(0xff557466), height: 1.35)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.74),
            border: Border.all(color: const Color(0xffd7e8dd)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Screening only. This app does not diagnose RLS or determine whether you have RLS.'),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Colors.white.withOpacity(0.88),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xffd7e8dd)),
          ),
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
        const SizedBox(height: 18),
        const FooterBadge(),
      ],
    );
  }
}

class FooterBadge extends StatelessWidget {
  const FooterBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        border: Border.all(color: const Color(0xffd7e8dd)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          RlsLogoMark(size: 34),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('research-ops@rls-screen.local', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                Text('Mobile MVP logs: Flutter console + FastAPI terminal', style: TextStyle(color: Color(0xff557466), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
