import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'api_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:url_launcher/url_launcher.dart';
import 'call_detection_service.dart';
import 'record_page.dart';
import 'tutorial_page.dart';

Future<void> openPrivacyPolicy() async {
  final uri = Uri.parse(
    'https://voicedetector1.netlify.app/',
  );

  if (!await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  )) {
    throw Exception('Could not open Privacy Policy');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeController.instance.load();
  await CallDetectionService.instance.restoreIfEnabled();

  void open(String action) => navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => RecordPage(
          autoStart: action == 'allow', askToStart: action != 'allow')));

  CallDetectionService.instance.onAction = open;
  CallDetectionService.instance.listenForActions();

  runApp(const VoiceDetectorApp());

  final initial = await CallDetectionService.instance.initialAction();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => open(initial));
  }
}

const purple = Color(0xFF5147E8);
const purpleDark = Color(0xFF3436B9);
const blue = Color(0xFF29A7D9);
const ink = Color(0xFF18213F);
const muted = Color(0xFF6E7692);
const page = Color(0xFFF7F8FE);
const green = Color(0xFF079B70);
const red = Color(0xFFE83E5B);
final navigatorKey = GlobalKey<NavigatorState>();

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();
  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('themeMode') ?? 'system';
    mode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode value) async {
    mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }
}

class VoiceDetectorApp extends StatelessWidget {
  const VoiceDetectorApp({super.key});

  ThemeData _lightTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: page,
    colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.light),
    appBarTheme: const AppBarTheme(backgroundColor: purple, foregroundColor: Colors.white,
      centerTitle: true, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  ThemeData _darkTheme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF242044), foregroundColor: Colors.white,
      centerTitle: true, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: const Color(0xFF292A3D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ThemeController.instance,
    builder: (context, _) => MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Voice Detector',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: ThemeController.instance.mode,
      home: const AuthGate(),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) return const HomePage();
        return const RegisterPage();
      },
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}
class _RegisterPageState extends State<RegisterPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final age = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  bool isLogin = false;
  bool submitting = false;

  @override
  void dispose() {
    name.dispose(); email.dispose(); age.dispose(); phone.dispose(); password.dispose();
    super.dispose();
  }

  Widget input(String label, IconData icon, TextEditingController c, {TextInputType? type, bool obscure = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        obscureText: obscure,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: purple, size: 20),
          hintText: label,
        ),
      ),
    );

  Future<void> submitAuth() async {
    final emailValue = email.text.trim();
    final passwordValue = password.text;
    if (!emailValue.contains('@') || passwordValue.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email and a password of at least 6 characters.')),
      );
      return;
    }
    if (!isLogin && (name.text.trim().isEmpty || age.text.trim().isEmpty || phone.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all registration fields.')),
      );
      return;
    }

    setState(() => submitting = true);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailValue,
          password: passwordValue,
        );
      } else {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailValue,
          password: passwordValue,
        );
        await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({
          'name': name.text.trim(),
          'email': emailValue,
          'age': int.tryParse(age.text.trim()),
          'phone': phone.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      // AuthGate listens to authStateChanges() and opens HomePage automatically.
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'email-already-in-use' => 'An account already exists for this email.',
        'invalid-email' => 'Please enter a valid email address.',
        'weak-password' => 'Choose a stronger password.',
        'user-not-found' => 'No account found for this email.',
        'wrong-password' || 'invalid-credential' => 'Email or password is incorrect.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        _ => e.message ?? 'Authentication failed.',
      };
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete this action: $e')),
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.graphic_eq_rounded, size: 70, color: purple),
                const SizedBox(height: 10),
                const Text('Voice Detector', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 7),
                const Text('Detect AI-generated voices', textAlign: TextAlign.center,
                  style: TextStyle(color: purple, fontWeight: FontWeight.w500)),
                const SizedBox(height: 30),
                if (!isLogin) ...[
                  input('Full Name', Icons.person, name),
                  input('Age', Icons.calendar_month_outlined, age, type: TextInputType.number),
                  input('Phone number', Icons.phone_outlined, phone, type: TextInputType.phone),
                ],
                input('Email address', Icons.email_outlined, email, type: TextInputType.emailAddress),
                input('Password (at least 6 characters)', Icons.lock_outline, password, obscure: true),
                const SizedBox(height: 12),
                GradientButton(
                  label: submitting ? 'Please wait...' : (isLogin ? 'Sign In' : 'Register and Continue'),
                  onTap: submitting ? () {} : submitAuth,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: submitting ? null : () => setState(() => isLogin = !isLogin),
                  child: Text(isLogin ? 'New user? Create an account' : 'Already registered? Sign in'),
                ),
                const SizedBox(height: 18),
                const Text('Your audio is analyzed only when you choose a recording.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      final records = await FirebaseService().loadRecentAnalysis();
      if (!mounted) return;
      setState(() {
        history
          ..clear()
          ..addAll(records.map((data) => AnalysisRecord(
            data['filename'] as String? ?? 'audio',
            (data['aiScore'] as num?)?.toDouble() ?? 0.0,
            (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          )));
      });
    } catch (e) {
      debugPrint('Could not load analysis history: $e');
    }
  }

  String? path;
  String? filename;
  bool busy = false;
  String status = 'Choose a recording to get started.';
  double? score;
  String? resultText;
  final List<AnalysisRecord> history = [];

  Future<void> showPermissionInfo() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const CircleAvatar(radius: 28, backgroundColor: Color(0xFFEDEBFF),
          child: Icon(Icons.shield_outlined, color: purple, size: 30)),
        title: const Text('Permissions Required', textAlign: TextAlign.center),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('To analyze voice recordings, choose a saved audio file from your device.',
            textAlign: TextAlign.center),
          SizedBox(height: 18),
          PermissionLine(icon: Icons.mic_none, title: 'Microphone',
            subtitle: 'Needed only if you later enable in-app recording.'),
          PermissionLine(icon: Icons.folder_outlined, title: 'Audio files',
            subtitle: 'Select a recording using Android’s file picker.'),
          PermissionLine(icon: Icons.notifications_none, title: 'Notifications',
            subtitle: 'May be used for incoming-call alerts where supported.'),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (proceed == true) await pickAudio();
  }

  Future<void> pickAudio() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'amr', '3gp'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final f = picked.files.single;
      if (f.path == null) {
        setState(() => status = 'Could not access the selected file. Please choose another.');
        return;
      }
      setState(() {
        path = f.path; filename = f.name; score = null; resultText = null;
        status = 'Recording ready for analysis.';
      });
    } catch (e) {
      setState(() => status = 'Could not select audio: $e');
    }
  }

  Future<void> analyze() async {
    if (path == null) { await showPermissionInfo(); return; }
    setState(() { busy = true; status = 'Uploading audio and analyzing...'; score = null; resultText = null; });
    try {
      final result = await VoiceApi().predict(path!);
      final raw = result['ai_score'];
      if (raw is num && raw >= 0 && raw <= 1) {
        final s = raw.toDouble();
        final analysisLabel = s > 0.5
            ? 'Possible AI-generated voice'
            : 'Likely human voice';
        try {
          await FirebaseService().saveAnalysis(
            filename: filename ?? 'audio',
            aiScore: s,
            result: analysisLabel,
          );
        } catch (e) {
          debugPrint('Could not save analysis to Firestore: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Analysis completed, but saving history failed.')),
            );
          }
        }
        setState(() {
          score = s;
          status = s > 0.5 ? 'Possible AI-generated voice' : 'Likely human voice';
          history.insert(0, AnalysisRecord(filename ?? 'audio', s, DateTime.now()));
        });
        if (mounted) {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => ResultPage(filename: filename ?? 'Recording', score: s)));
        }
      } else {
        setState(() { resultText = '${result['result'] ?? result}'; status = 'Prediction received'; });
      }
    } catch (e) {
      setState(() => status = 'Analysis failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openImportPage() async {
    final selectedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ImportPage(),
      ),
    );

    if (selectedPath != null && mounted) {
      setState(() {
        path = selectedPath;
        filename = selectedPath.split(RegExp(r'[/\\]')).last;
        score = null;
        resultText = null;
        status = 'Recording ready for analysis.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const CallDetectionSwitch(compact: true),
      leadingWidth: 112,
      
      title: const Text('Voice Detector', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
          },
        ),
        IconButton(tooltip: 'Profile', icon: const Icon(Icons.account_circle_outlined), onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
        }),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
      onDestinationSelected: (i) {
        if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
        if (i == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
      },
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7453F5), Color(0xFF26A7D8)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: purple.withOpacity(.16), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: const Row(children: [
              Icon(Icons.graphic_eq, color: Colors.white, size: 48),
              SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Detect suspicious voices', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 7),
                Text('Analyze audio to check whether it may be human or AI-generated.',
                  style: TextStyle(color: Colors.white, height: 1.35)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5E8F5))),
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              leading: const CircleAvatar(backgroundColor: Color(0xFFEAE8FF),
                child: Icon(Icons.folder_open, color: purple)),
              title: const Text('Import Recording', style: TextStyle(fontWeight: FontWeight.bold, color: ink)),
              subtitle: Text(filename ?? 'Choose a saved call recording from your device.'),
              trailing: const Icon(Icons.chevron_right, color: muted),
              onTap: openImportPage,
            ),
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Recent Analysis', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: ink)),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage())),
              child: const Text('View all')),
          ]),
          if (history.isEmpty)
            const EmptyHistory()
          else
            ...history.take(5).map((r) => AnalysisTile(record: r, onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ResultPage(filename: r.name, score: r.score))))),
          if (filename != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : analyze,
              icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search),
              label: Text(busy ? 'Analyzing...' : 'Analyze selected recording'),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: 14), const LinearProgressIndicator(),
            const SizedBox(height: 8), Text(status, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
          ],
          if (resultText != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('$status\n$resultText'))),
          const SizedBox(height: 14),
          const Text('Note: voice detection is an estimate, not proof of cloning.',
            textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<Map<String, dynamic>> _profile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return doc.data() ?? {};
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _profile(),
          builder: (context, snapshot) {
            final data = snapshot.data ?? {};
            final name = (data['name'] as String?)?.trim();
            final displayName = (name != null && name.isNotEmpty) ? name : (user?.displayName ?? 'Voice Detector user');
            return Column(children: [
              CircleAvatar(radius: 42, backgroundColor: const Color(0xFFEAE8FF),
                child: const Icon(Icons.person, color: purple, size: 44)),
              const SizedBox(height: 12),
              Text(displayName, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(user?.email ?? '', style: Theme.of(context).textTheme.bodyMedium),
            ]);
          },
        ),
        const SizedBox(height: 26),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.privacy_tip_outlined, color: purple),
            title: const Text('Privacy Policy'), subtitle: const Text('How your information and audio are handled'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openPrivacyPolicy()),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.feedback_outlined, color: purple),
            title: const Text('Feedback'), subtitle: const Text('Share suggestions or report a problem'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackPage()))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.settings_outlined, color: purple),
            title: const Text('Settings'), subtitle: const Text('Appearance and app preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.logout, color: red), title: const Text('Log out'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) Navigator.popUntil(context, (route) => route.isFirst);
            }),
        ])),
      ]),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Appearance', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Choose how Voice Detector looks on this device.'),
      const SizedBox(height: 12),
      Card(child: Column(children: [
        RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: ThemeController.instance.mode,
          secondary: const Icon(Icons.light_mode_outlined), title: const Text('Light mode'),
          onChanged: (value) { if (value != null) ThemeController.instance.setMode(value); }),
        RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: ThemeController.instance.mode,
          secondary: const Icon(Icons.dark_mode_outlined), title: const Text('Dark mode'),
          onChanged: (value) { if (value != null) ThemeController.instance.setMode(value); }),
        RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: ThemeController.instance.mode,
          secondary: const Icon(Icons.settings_brightness_outlined), title: const Text('Use device setting'),
          onChanged: (value) { if (value != null) ThemeController.instance.setMode(value); }),
      ])),
      const SizedBox(height: 24),
      Text('Calls', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Card(child: CallDetectionSwitch()),
      const SizedBox(height: 18),
      ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy Policy'),
        trailing: const Icon(Icons.open_in_new), onTap: () => openPrivacyPolicy()),
      ListTile(leading: const Icon(Icons.feedback_outlined), title: const Text('Send Feedback'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackPage()))),
    ]),
  );
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy Policy')),
    body: ListView(padding: const EdgeInsets.all(20), children: const [
      Text('Voice Detector Privacy Policy', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      SizedBox(height: 12),
      Text('Information collected: when you create an account, the app stores the profile information you provide, such as name, email, age and phone number, in Firebase. Firebase Authentication handles sign-in credentials.'),
      SizedBox(height: 12),
      Text('Audio processing: when you choose to analyze a recording, the app sends the selected audio to the configured Voice Detector analysis server to obtain a prediction. Do not submit audio unless you have permission to use it.'),
      SizedBox(height: 12),
      Text('Analysis history: the app stores the recording filename, prediction score, result label and timestamp in your account history in Firebase Firestore.'),
      SizedBox(height: 12),
      Text('Sharing and retention: data is handled by the configured Firebase project and analysis server. The developer should specify the server provider’s retention practices, account/data deletion process and a contact email before publishing this policy.'),
      SizedBox(height: 12),
      Text('Accuracy: voice detection results are estimates and should not be treated as conclusive proof.'),
      SizedBox(height: 12),
      Text('Before publishing: replace this draft with a complete policy that names the developer, provides a contact email, explains deletion/retention, and accurately reflects your server and Firebase configuration.'),
    ]),
  );
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _controller = TextEditingController();
  String _type = 'Suggestion';
  bool _sending = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    final message = _controller.text.trim();
    if (user == null) return;
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your feedback.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('feedback').add({
        'userId': user.uid,
        'email': user.email,
        'type': _type,
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you! Your feedback was sent.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send feedback: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Feedback')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Help us improve Voice Detector. Tell us what worked or what needs fixing.'),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(value: _type, decoration: const InputDecoration(labelText: 'Feedback type'),
        items: const [DropdownMenuItem(value: 'Suggestion', child: Text('Suggestion')),
          DropdownMenuItem(value: 'Bug report', child: Text('Bug report')),
          DropdownMenuItem(value: 'Other', child: Text('Other'))],
        onChanged: (value) { if (value != null) setState(() => _type = value); }),
      const SizedBox(height: 14),
      TextField(controller: _controller, minLines: 5, maxLines: 8,
        decoration: const InputDecoration(labelText: 'Your feedback', hintText: 'Write your message here...')),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: _sending ? null : _submit,
        icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
        label: Text(_sending ? 'Sending...' : 'Submit feedback')),
    ]),
  );
}

class PermissionPage extends StatelessWidget {
  const PermissionPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Permissions & Privacy')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.shield_outlined, color: purple, size: 64),
      const SizedBox(height: 16),
      const Text('Your privacy matters', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: ink)),
      const SizedBox(height: 12),
      const Text('Voice Detector analyzes audio only after you choose a recording. The file is sent to your configured analysis server.',
        textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.5)),
      const SizedBox(height: 24),
      const PermissionLine(icon: Icons.folder_outlined, title: 'Audio file access',
        subtitle: 'Android’s file picker lets you choose a recording without granting broad storage access.'),
      const PermissionLine(icon: Icons.mic_none, title: 'Microphone',
        subtitle: 'Not requested for importing a saved recording. Required only for an in-app recording feature.'),
      const PermissionLine(icon: Icons.notifications_none, title: 'Notifications',
        subtitle: 'An incoming-call alert can be added where Android and device rules permit.'),
    ]),
  );
}

class PermissionLine extends StatelessWidget {
  final IconData icon; final String title; final String subtitle;
  const PermissionLine({super.key, required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: purple, size: 24), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: ink)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: muted, height: 1.35)),
      ])),
    ]),
  );
}

class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  Future<void> selectAudio(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;

      if (file.path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access the selected audio file.'),
          ),
        );
        return;
      }

      Navigator.pop(context, file.path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to select audio: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF18213F),
        elevation: 0,
        title: const Text('Import Recording'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const CircleAvatar(
                radius: 46,
                backgroundColor: Color(0xFFEAE8FF),
                child: Icon(
                  Icons.music_note,
                  size: 46,
                  color: Color(0xFF5147E8),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Call Recording',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Choose a saved recording from your device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => selectAudio(context),
                  child: const Padding(
                    padding: EdgeInsets.all(15),
                    child: Text('Select Audio File'),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Select an audio file in a supported format. '
                'Some formats may require conversion before analysis.',
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'WAV', 'MP3', 'M4A', 'AAC', 'AMR', '3GP',
                ].map((format) => Chip(label: Text(format))).toList(),
              ),
              const Spacer(),
              const Text(
                'Only select audio you have permission to use.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  final String filename; final double score;
  const ResultPage({super.key, required this.filename, required this.score});
  @override
  Widget build(BuildContext context) {
    final isAi = score > 0.5;
    final color = isAi ? red : green;
    final percent = (score * 100).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis Result'), leading: IconButton(
        icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(22), children: [
        const SizedBox(height: 20),
        CircleAvatar(radius: 46, backgroundColor: color.withOpacity(.12),
          child: Icon(isAi ? Icons.smart_toy_outlined : Icons.person, color: color, size: 48)),
        const SizedBox(height: 20),
        Text(isAi ? 'Possible AI-generated voice' : 'Likely human voice',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 12),
        Text('AI Score: $percent%', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ink)),
        const SizedBox(height: 18),
        ClipRRect(borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(value: score, minHeight: 12,
            backgroundColor: const Color(0xFFE5E8F2), color: color)),
        const SizedBox(height: 10),
        Text(filename, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
        const SizedBox(height: 22),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.withOpacity(.09), borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(isAi ? Icons.error_outline : Icons.info_outline, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(isAi
              ? 'The model found patterns associated with AI-generated voices. This result is not conclusive.'
              : 'The model did not detect strong signs of AI-generated speech. This result is not conclusive.',
              style: TextStyle(color: ink, height: 1.4))),
          ]),
        ),
        const SizedBox(height: 24),
        GradientButton(label: 'New Analysis', onTap: () => Navigator.pop(context)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
          child: const Text('Back to Home')),
      ])),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Analysis History')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: FirebaseService().loadRecentAnalysis(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load history. Please try again.'));
        }
        final data = snapshot.data ?? [];
        if (data.isEmpty) return const EmptyHistory();
        final records = data.map((item) => AnalysisRecord(
          item['filename'] as String? ?? 'audio',
          (item['aiScore'] as num?)?.toDouble() ?? 0.0,
          (item['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        )).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: records.map((r) => AnalysisTile(
            record: r,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ResultPage(filename: r.name, score: r.score)),
            ),
          )).toList(),
        );
      },
    ),
  );
}

class AnalysisRecord {
  final String name; final double score; final DateTime time;
  AnalysisRecord(this.name, this.score, this.time);
}

class AnalysisTile extends StatelessWidget {
  final AnalysisRecord record; final VoidCallback onTap;
  const AnalysisTile({super.key, required this.record, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ai = record.score > .5;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Color(0xFFE8EAF5))),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: ai ? const Color(0xFFFFE8EC) : const Color(0xFFE1F7EF),
          child: Icon(Icons.music_note, color: ai ? red : green)),
        title: Text(record.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('${ai ? "Possible AI voice" : "Human-like voice"} • ${record.time.toLocal()}',
          style: TextStyle(color: ai ? red : green, fontSize: 12)),
        trailing: Text('${(record.score * 100).round()}%',
          style: const TextStyle(fontWeight: FontWeight.bold, color: ink)),
      ),
    );
  }
}

class EmptyHistory extends StatelessWidget {
  const EmptyHistory({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE8EAF5))),
    child: const Column(children: [
      Icon(Icons.history, color: Color(0xFF9BA2BC), size: 40),
      SizedBox(height: 10),
      Text('No analysis yet', style: TextStyle(fontWeight: FontWeight.bold, color: ink)),
      SizedBox(height: 5),
      Text('Your recent results will appear here.', textAlign: TextAlign.center,
        style: TextStyle(color: muted)),
    ]),
  );
}

class GradientButton extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const GradientButton({super.key, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [purple, Color(0xFF6358F0)]),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: purple.withOpacity(.18), blurRadius: 12, offset: const Offset(0, 5))],
    ),
    child: Material(color: Colors.transparent, child: InkWell(
      borderRadius: BorderRadius.circular(14), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      ),
    )),
  );
}

/// Live Call Detection allow / don't allow switch.
/// fancy: true  -> gradient card used on Home.
/// fancy: false -> plain tile used in Settings.
/// Both share one ValueNotifier, so they always show the same state.
class CallDetectionSwitch extends StatefulWidget {
  final bool fancy;
  final bool compact;
  const CallDetectionSwitch({super.key, this.fancy = false, this.compact = false});
  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  @override
  State<CallDetectionSwitch> createState() => _CallDetectionSwitchState();
}

class _CallDetectionSwitchState extends State<CallDetectionSwitch> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CallDetectionService.instance.isEnabled().then((v) {
      CallDetectionSwitch.enabled.value = v;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
                final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
        final prefs = await SharedPreferences.getInstance();
        final seenKey = 'liveCallTutorialSeen_$uid';
        if (!(prefs.getBool(seenKey) ?? false)) {
          if (!mounted) return;
          final watched = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const LiveCallTutorialPage()),
          );
          if (watched != true) return;
          await prefs.setBool(seenKey, true);
        }
        if (!mounted) return;
        final agreed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Live Call Detection'),
            content: RichText(
  text: TextSpan(
    style: const TextStyle(
      fontSize: 14,
      color: Colors.black,
      height: 1.5,
    ),
    children: [
      TextSpan(
        text: 'While these feature want to work means the Voice Detector app must running in the background and have access to phone and notification permissions.\n\n',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
      const TextSpan(
        text: 'Voice Detector can detect incoming call activity and notify you. '
            'It does not automatically record phone calls.\n\n'
            'If you choose to record, your microphone will be used. You can stop '
            'recording at any time. If you analyze a recording, the audio will be '
            'uploaded to our server for AI analysis.\n\n'
            'Recording a call on speakerphone may not capture both voices, and you '
            'must make sure everyone on the call is informed and has agreed where '
            'the law requires it.',
      ),
    ],
  ),
),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Don't allow")),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow')),
            ],
          ),
        );
        if (agreed != true) return;
        final ok = await CallDetectionService.instance.enable();
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Phone and notification permissions are needed for call alerts.'),
          ));
        }
        CallDetectionSwitch.enabled.value = ok;
      } else {
        await CallDetectionService.instance.disable();
        CallDetectionSwitch.enabled.value = false;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
    Widget _compactPill(bool on) => Padding(
    padding: const EdgeInsets.only(left: 10, top: 9, bottom: 9),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _busy ? null : () => _toggle(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: on
                  ? const [Color(0xFF079B70), Color(0xFF26C6A0)]
                  : const [Color(0x33FFFFFF), Color(0x22FFFFFF)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(on ? .6 : .35)),
            boxShadow: on
                ? [BoxShadow(color: green.withOpacity(.55), blurRadius: 10)]
                : const [],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.phone_in_talk : Icons.phone_disabled,
                color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Call alert',
                    style: TextStyle(color: Colors.white70, fontSize: 9.5, height: 1.1)),
                Text(on ? 'ON' : 'OFF',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
              ],
            ),
          ]),
        ),
      ),
    ),
  );

  Widget _step(IconData icon, String label) => Expanded(
    child: Column(children: [
      Icon(icon, color: Colors.white, size: 20),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.2)),
    ]),
  );

  Widget _fancyCard(bool on) => AnimatedContainer(
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeInOut,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: on
            ? const [Color(0xFF079B70), Color(0xFF26A7D8)]
            : const [Color(0xFF3F4468), Color(0xFF6A6F96)],
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: (on ? green : purple).withOpacity(.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(children: [
      Row(children: [
        Stack(alignment: Alignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: on ? 68 : 56,
            height: on ? 68 : 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(on ? .16 : .08),
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(.22)),
            child: Icon(
              on ? Icons.phone_in_talk : Icons.phone_disabled,
              color: Colors.white,
              size: 26,
            ),
          ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: on ? const Color(0xFFB9FFE5) : Colors.white54),
                const SizedBox(width: 5),
                Text(on ? 'ACTIVE' : 'OFF',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .8)),
              ]),
            ),
            const SizedBox(height: 7),
            const Text('Live Call Detection',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(
              on ? 'You will be asked before any recording.' : 'Allow to get an alert when a call rings.',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3)),
          ]),
        ),
        Switch(
          value: on,
          onChanged: _busy ? null : _toggle,
          activeColor: Colors.white,
          activeTrackColor: Colors.white38,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Colors.white24,
        ),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _step(Icons.ring_volume, 'Call rings'),
          const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
          _step(Icons.touch_app_outlined, 'Tap Allow\nor Don\'t allow'),
          const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
          _step(Icons.mic_none, 'Record,\nthen check'),
        ]),
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: CallDetectionSwitch.enabled,
    builder: (context, on, _) {
      if (widget.compact) return _compactPill(on);
      if (widget.fancy) return _fancyCard(on);
      return SwitchListTile(
        secondary: const Icon(Icons.phone_in_talk_outlined, color: purple),
        title: const Text('Live Call Detection', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(on
            ? 'Allowed. You will be asked before any recording.'
            : 'Not allowed. Turn on to get call alerts.'),
        value: on,
        onChanged: _busy ? null : _toggle,
      );
    },
  );
}

// Firebase Authentication and Firestore operations used by the screens above.
class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveAnalysis({
    required String filename,
    required double aiScore,
    required String result,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please sign in before saving analysis.');

    await _db.collection('analysis').add({
      'userId': user.uid,
      'filename': filename,
      'aiScore': aiScore,
      'result': result,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> loadRecentAnalysis() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please sign in to view analysis history.');

    final snapshot = await _db
        .collection('analysis')
        .where('userId', isEqualTo: user.uid)
        .get();
    final records = snapshot.docs.map((doc) => <String, dynamic>{
      'id': doc.id,
      ...doc.data(),
    }).toList();

    records.sort((a, b) {
      final aTime = a['timestamp'] as Timestamp?;
      final bTime = b['timestamp'] as Timestamp?;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return records;
  }
}