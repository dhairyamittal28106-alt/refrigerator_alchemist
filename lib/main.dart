import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // Required for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: unused_import
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path_utils;

// --- FIREBASE IMPORTS ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

// --- ADMOB IMPORT ---
import 'package:google_mobile_ads/google_mobile_ads.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Mobile Ads SDK
  await MobileAds.instance.initialize();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await dotenv.load(fileName: ".env");

  try {
    cameras = await availableCameras();
  } catch (e) {
    cameras = [];
    print("Camera init error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RecipeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
        primaryColor: const Color(0xFF00FFC2),
        textTheme: GoogleFonts.outfitTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFC2),
          secondary: Color(0xFF6E44FF),
          surface: Color(0xFF1A1A1A),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ==================== AUTHENTICATION LOGIC ====================

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get user => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --- GOOGLE SIGN IN ---
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      notifyListeners();
    } catch (e) {
      print("Google Sign In Error: $e");
      rethrow;
    }
  }

  // --- EMAIL SIGN IN / UP ---
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    notifyListeners();
  }

  Future<void> signUpWithEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
    notifyListeners();
  }

  // --- SIGN OUT ---
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    notifyListeners();
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFF00FFC2))));
        }
        if (snapshot.hasData) {
          return const RefrigeratorAlchemist();
        } else {
          return const LoginPage();
        }
      },
    );
  }
}

// ==================== PREMIUM LOGIN UI (DARK MODE) ====================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  int _authMode = 0; // 0: Google, 1: Email
  bool _isLoading = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF00FFC2),
        behavior: SnackBarBehavior.floating,
      )
    );
  }

  Future<void> _handleGoogle() async {
    setState(() => _isLoading = true);
    try {
      await Provider.of<AuthProvider>(context, listen: false).signInWithGoogle();
    } catch (e) {
      _showMessage("Google Sign In Failed", isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleEmail(bool isLogin) async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (isLogin) {
        await auth.signInWithEmail(_emailCtrl.text.trim(), _passCtrl.text.trim());
      } else {
        await auth.signUpWithEmail(_emailCtrl.text.trim(), _passCtrl.text.trim());
      }
    } catch (e) {
      _showMessage(e.toString(), isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background - NEW DARK IMAGE (Moody Ingredients)
          Positioned.fill(
            child: Image.network(
              "https://images.unsplash.com/photo-1516684732162-798a0062be99?q=80&w=1000&auto=format&fit=crop", 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF0F1115)),
            ),
          ),
          // Heavy Gradient to blend text
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.4), Colors.black],
                ),
              ),
            ),
          ),
          
          // Main Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_awesome, size: 60, color: Color(0xFF00FFC2)),
                    const SizedBox(height: 20),
                    Text("Fridge Alchemist", style: GoogleFonts.playfairDisplay(fontSize: 36, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    const Text("Turn ingredients into magic.", style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 40),

                    GlassContainer(
                      opacity: 0.15,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _toggleBtn(Icons.g_mobiledata, 0),
                                _toggleBtn(Icons.email_outlined, 1),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),

                          if (_isLoading) 
                            const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF00FFC2)))
                          else 
                            _buildAuthForm(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn(IconData icon, int index) {
    final isSelected = _authMode == index;
    return GestureDetector(
      onTap: () => setState(() => _authMode = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 35),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00FFC2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: isSelected ? Colors.black : Colors.white54, size: 28),
      ),
    );
  }

  Widget _buildAuthForm() {
    switch (_authMode) {
      case 0: // GOOGLE
        return GestureDetector(
          onTap: _handleGoogle,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Center(
              child: Text("Continue with Google", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        );
      
      case 1: // EMAIL
        return Column(
          children: [
            _inputField(_emailCtrl, "Email Address", Icons.email),
            const SizedBox(height: 15),
            _inputField(_passCtrl, "Password", Icons.lock, isPass: true),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(child: _actionBtn("Sign Up", () => _handleEmail(false), isOutline: true)),
                const SizedBox(width: 10),
                Expanded(child: _actionBtn("Login", () => _handleEmail(true))),
              ],
            )
          ],
        );

      default: return const SizedBox.shrink();
    }
  }

  Widget _inputField(TextEditingController ctrl, String hint, IconData icon, {bool isPass = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isPass,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white54),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF00FFC2))),
      ),
    );
  }

  Widget _actionBtn(String text, VoidCallback onTap, {bool isOutline = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isOutline ? Colors.transparent : const Color(0xFF00FFC2),
          border: isOutline ? Border.all(color: const Color(0xFF00FFC2)) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(child: Text(text, style: TextStyle(color: isOutline ? const Color(0xFF00FFC2) : Colors.black, fontWeight: FontWeight.bold))),
      ),
    );
  }
}

// ==================== LOGIC CLASSES (Clarifai/OpenRouter) ====================

class ClarifaiClient {
  final String pat;
  ClarifaiClient({required this.pat});
  Future<Map<String, dynamic>> detectFoodBase64(String base64Image) async {
    final uri = Uri.parse("https://api.clarifai.com/v2/models/food-item-recognition/versions/1d5fd481e0cf4826aa72ec3ff049e044/outputs");
    final body = {"user_app_id": {"user_id": "clarifai", "app_id": "main"}, "inputs": [{"data": {"image": {"base64": base64Image}}}]};
    final res = await http.post(uri, headers: {"Authorization": "Key $pat", "Content-Type": "application/json"}, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception("Clarifai detect failed (${res.statusCode}): ${res.body}");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

Future<Map<String, dynamic>> detectFile(String path) async {
  final pat = dotenv.env['CLARIFAI_PAT'] ?? "";
  if (pat.isEmpty) throw Exception("Missing CLARIFAI_PAT in .env");
  final client = ClarifaiClient(pat: pat);
  final file = File(path);
  if (!await file.exists()) throw Exception("File not found: $path");
  final bytes = await file.readAsBytes();
  return await client.detectFoodBase64(base64Encode(bytes));
}

Map<String, dynamic> mergeDetectJsons(List<Map<String, dynamic>> list) {
  final Map<String, double> best = {};
  for (final detect in list) {
    try {
      final outputs = (detect['outputs'] as List?) ?? [];
      if (outputs.isEmpty) continue;
      final data = outputs[0]['data'] as Map<String, dynamic>? ?? {};
      final concepts = (data['concepts'] as List?) ?? [];
      for (final c in concepts) {
        if (c is Map) {
          final name = c['name']?.toString().toLowerCase().trim();
          final value = c['value'];
          if (name == null || value == null) continue;
          final score = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
          if (!best.containsKey(name) || best[name]! < score) best[name] = score;
        }
      }
    } catch (e) { print("merge parse error: $e"); }
  }
  final conceptsList = best.entries.map((e) => {"name": e.key, "value": e.value}).toList();
  return { "outputs": [ { "data": {"concepts": conceptsList} } ] };
}

Future<String> generateWithOpenRouter(String prompt) async {
  final key = dotenv.env['OPENROUTER_KEY']?.trim() ?? "";
  final base = (dotenv.env['OPENROUTER_BASE_URL'] ?? "https://openrouter.ai/api/v1").trim().replaceAll(RegExp(r'/$'), '');
  final model = dotenv.env['OPENROUTER_MODEL']?.trim() ?? "deepseek/deepseek-chat";
  if (key.isEmpty) throw Exception("Missing OPENROUTER_KEY in .env");

  final uri = Uri.parse("$base/chat/completions");
  final body = { "model": model, "messages": [ {"role": "user", "content": prompt} ], "temperature": 0.25, "max_tokens": 450 };

  http.Response res;
  try {
    res = await http.post(uri, headers: {"Content-Type": "application/json", "Authorization": "Bearer $key"}, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
  } catch (_) {
    final uri2 = Uri.parse("$base/v1/chat/completions");
    res = await http.post(uri2, headers: {"Content-Type": "application/json", "Authorization": "Bearer $key"}, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
  }
  if (res.statusCode < 200 || res.statusCode >= 300) throw Exception("OpenRouter request failed (${res.statusCode}): ${res.body}");
  return _parseOpenRouterResponse(res.body);
}

String _parseOpenRouterResponse(String body) {
  final dynamic jsonResp = jsonDecode(body);
  if (jsonResp is Map && jsonResp.containsKey('choices')) {
    final choices = jsonResp['choices'] as List;
    if (choices.isNotEmpty) {
      final first = choices[0];
      if (first is Map && first.containsKey('message') && first['message'] is Map) {
        final content = first['message']['content'];
        if (content is String && content.trim().isNotEmpty) return content.trim();
      }
    }
  }
  return body; 
}

// --- UPDATED INGREDIENT SELECTOR WITH VERY LOW THRESHOLDS ---
List<String> _selectIngredientsFromDetectJson(Map<String, dynamic> detectJson) {
  final Map<String, double> bestScores = {};
  
  // 1. INGREDIENT THRESHOLD (30%)
  const double ingredientThreshold = 0.30; 
  
  // 2. SAFETY THRESHOLD (40%)
  const double safetyThreshold = 0.40;
  
  double highestScoreFound = 0.0;

  try {
    final outputs = (detectJson["outputs"] as List?) ?? [];
    for (final out in outputs) {
      try {
        final data = out?["data"] as Map<String, dynamic>? ?? {};
        final concepts = (data["concepts"] as List?) ?? [];
        for (final c in concepts) {
          if (c is Map) {
            final name = c["name"]?.toString().toLowerCase().trim() ?? "";
            final val = c["value"];
            final score = (val is num) ? val.toDouble() : double.tryParse(val.toString()) ?? 0.0;
            
            // Track max confidence
            if (score > highestScoreFound) highestScoreFound = score;

            // Add if > 30%
            if (score >= ingredientThreshold) {
              if (name.isNotEmpty && (!bestScores.containsKey(name) || bestScores[name]! < score)) {
                bestScores[name] = score;
              }
            }
          }
        }
      } catch (_) {}
    }
  } catch (e) { print("Ingredient extraction error: $e"); }

  // 3. FINAL DECISION:
  if (bestScores.isEmpty || highestScoreFound < safetyThreshold) {
    throw Exception("NOT_FOOD");
  }

  return bestScores.keys.take(8).map((e) => e.replaceAll(RegExp(r'[^\w\s\-]'), '').trim()).toList();
}

Future<String> generateRecipeFromPaths(List<String> imagePaths) async {
  if (imagePaths.isEmpty) throw Exception("No images provided");
  final List<Map<String, dynamic>> detects = [];
  for (final p in imagePaths) detects.add(await detectFile(p));
  final merged = mergeDetectJsons(detects);
  
  final ingredients = _selectIngredientsFromDetectJson(merged);

  final prompt = """
You are a 5-star Michelin chef. I have: ${ingredients.join(", ")}.
Create a sophisticated yet doable recipe.
Return strict JSON:
{ "dish": "Dish Name", "ingredients": "• Item 1\\n• Item 2", "steps": "1. Step one...\\n2. Step two..." }
Do NOT use markdown.
""";
  final raw = await generateWithOpenRouter(prompt);
  final cleaned = raw.replaceAll("```json", "").replaceAll("```", "").trim();
  try { jsonDecode(cleaned); return cleaned; } catch (_) { return raw; }
}

Future<String> generateRecipeWithClarifai(String imagePath) async => await generateRecipeFromPaths([imagePath]);

// ==================== PROVIDER (WITH FIRESTORE) ====================

class RecipeProvider extends ChangeNotifier {
  Map<String, String>? recipe;
  String? photoPath;
  List<Map<String, dynamic>> history = [];
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  RecipeProvider() { _loadHistory(); }

  void setRecipe(String path, String jsonText) {
    photoPath = path;
    final cleaned = jsonText.replaceAll("```json", "").replaceAll("```", "").trim();
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      recipe = {
        'dish': parsed['dish']?.toString() ?? 'Unknown Dish',
        'ingredients': parsed['ingredients']?.toString() ?? '',
        'steps': parsed['steps']?.toString() ?? '',
      };
    } catch (e) {
      recipe = {'dish': 'Chef\'s Suggestion', 'ingredients': '', 'steps': cleaned};
    }
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _db.collection('users').doc(user.uid).collection('recipes').orderBy('date', descending: true).get();
      history = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'dish': data['dish'],
          'ingredients': data['ingredients'],
          'steps': data['steps'],
          'date': data['date'],
          'imagePath': data['imagePath'],
        };
      }).toList();
      notifyListeners();
    } catch (e) { print("Error loading cloud history: $e"); }
  }

  Future<void> saveToHistory(Map<String, String> recipeData, String tempImagePath) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = path_utils.basename(tempImagePath);
      final newPath = path_utils.join(directory.path, fileName);
      await File(tempImagePath).copy(newPath);

      final entry = {
        'dish': recipeData['dish'],
        'ingredients': recipeData['ingredients'],
        'steps': recipeData['steps'],
        'imagePath': newPath,
        'date': DateTime.now().toIso8601String(),
        'user_email': user.email ?? user.phoneNumber ?? "Anonymous",
      };
      await _db.collection('users').doc(user.uid).collection('recipes').add(entry);
      await _loadHistory();
    } catch (e) { print("Error saving to cloud: $e"); }
  }

  Future<void> clearHistory() async { history.clear(); notifyListeners(); }
}

// ==================== UI UTILITIES ====================

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? color;
  final BorderRadius? borderRadius;
  final EdgeInsets padding;
  final EdgeInsets margin;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15,
    this.opacity = 0.1,
    this.color,
    this.borderRadius,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (color ?? Colors.white).withOpacity(opacity),
              borderRadius: borderRadius ?? BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ==================== MAIN SCREENS ====================

class RefrigeratorAlchemist extends StatefulWidget {
  const RefrigeratorAlchemist({super.key});
  @override
  State<RefrigeratorAlchemist> createState() => _RefrigeratorAlchemistState();
}

class _RefrigeratorAlchemistState extends State<RefrigeratorAlchemist> {
  int currentIndex = 1;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1115), Color(0xFF141414), Color(0xFF090A0C)],
          ),
        ),
        child: IndexedStack(index: currentIndex, children: const [HistoryPage(), HomeCarousel(), CameraPage()]),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 25, left: 20, right: 20),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(50),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          color: Colors.black,
          opacity: 0.6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.history_rounded, 0),
              _navItem(Icons.home_rounded, 1),
              _navItem(Icons.camera_alt_rounded, 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, int index) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFF00FFC2).withOpacity(0.2) : Colors.transparent, shape: BoxShape.circle),
        child: Icon(icon, color: isSelected ? const Color(0xFF00FFC2) : Colors.white54, size: 26),
      ),
    );
  }
}

class HomeCarousel extends StatelessWidget {
  const HomeCarousel({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 20.0, bottom: 10),
            child: Text("Fridge Alchemist", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          Expanded(
            child: PageView(
              controller: PageController(viewportFraction: 0.85),
              physics: const BouncingScrollPhysics(),
              children: const [ScanCard(), DynamicRecipeCard()],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class ScanCard extends StatelessWidget {
  const ScanCard({super.key});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CameraPage())),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          image: const DecorationImage(
            image: NetworkImage("https://images.unsplash.com/photo-1550989460-0adf9ea622e2?q=80&w=1000&auto=format&fit=crop"), // New Dark Grocery Image
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
          ),
          boxShadow: [BoxShadow(color: const Color(0xFF00FFC2).withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Stack(
          children: [
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: GlassContainer(
                opacity: 0.1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Identify Ingredients", style: GoogleFonts.dmSerifDisplay(fontSize: 26, color: Colors.white)),
                    const SizedBox(height: 8),
                    const Row(children: [Text("Tap to open camera", style: TextStyle(color: Colors.white70)), Spacer(), Icon(Icons.arrow_forward, color: Color(0xFF00FFC2))]),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class DynamicRecipeCard extends StatelessWidget {
  const DynamicRecipeCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<RecipeProvider>(builder: (context, provider, child) {
      if (provider.recipe == null) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white10)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant, size: 60, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 20),
              const Text("No Recipe Yet", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("Scan your fridge first", style: TextStyle(color: Colors.white54)),
            ],
          ),
        );
      }
      final recipe = provider.recipe!;
      final path = provider.photoPath;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Scaffold(
            backgroundColor: const Color(0xFF1E1E1E),
            body: Stack(
              children: [
                if (path != null) Positioned.fill(child: Image.file(File(path), fit: BoxFit.cover)),
                Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.8), Colors.black], stops: const [0.3, 0.6, 1.0])))),
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: path != null ? 200 : 50),
                        Text(recipe['dish'] ?? '', style: GoogleFonts.playfairDisplay(fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
                        const SizedBox(height: 20),
                        _sectionTitle("Ingredients"),
                        Text(recipe['ingredients'] ?? '', style: const TextStyle(color: Colors.white70, height: 1.6)),
                        const SizedBox(height: 20),
                        _sectionTitle("Instructions"),
                        Text(recipe['steps'] ?? '', style: const TextStyle(color: Colors.white70, height: 1.6)),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      );
    });
  }
  Widget _sectionTitle(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title.toUpperCase(), style: const TextStyle(color: Color(0xFF00FFC2), fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)));
  }
}

// ==================== CAMERA PAGE WITH INTERSTITIAL ADS ====================

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? controller;
  bool isInit = false;
  bool burstMode = false;
  InterstitialAd? _interstitialAd; // THE AD OBJECT

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadAd(); // LOAD AD WHEN CAMERA OPENS
  }

  // YOUR REAL AD UNIT ID from the screenshot: ca-app-pub-8295491395007414/9413676349
  void _loadAd() {
    InterstitialAd.load(
      adUnitId: Platform.isAndroid 
        ? 'ca-app-pub-8295491395007414/9413676349' // Real Android ID
        : 'ca-app-pub-3940256099942544/4411468910', // iOS (Test)
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          // Set up callbacks to handle closing the ad
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _loadAd(); // Preload next one
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _loadAd();
            },
          );
        },
        onAdFailedToLoad: (err) {
          print('Ad Failed to Load: $err');
        },
      ),
    );
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    controller = CameraController(cameras[0], ResolutionPreset.max, enableAudio: false);
    try {
      await controller!.initialize();
      if (mounted) setState(() => isInit = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    controller?.dispose();
    _interstitialAd?.dispose(); // CLEAN UP AD
    super.dispose();
  }

  // --- MODIFIED SNAP LOGIC ---
  Future<void> _snap() async {
    if (burstMode) {
      // 1. Capture Photos
      List<String> paths = [];
      for (int i = 0; i < 3; i++) {
        paths.add((await controller!.takePicture()).path);
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // 2. Show Ad, Then Navigate
      _showAdAndNavigate(() {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPageBurst(paths)));
      });

    } else {
      // 1. Capture Photo
      final file = await controller!.takePicture();
      
      // 2. Show Ad, Then Navigate
      _showAdAndNavigate(() {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPage(file.path)));
      });
    }
  }

  // Helper to show ad if ready, otherwise just run the function
  void _showAdAndNavigate(VoidCallback onDone) {
    if (_interstitialAd != null) {
      // Override the callback specifically for this navigation
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          onDone(); // Navigate AFTER ad closes
          _loadAd(); // Reload for next time
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          onDone(); // Navigate even if ad fails
          _loadAd();
        }
      );
      _interstitialAd!.show();
      _interstitialAd = null; // Clear reference so we don't show same ad twice
    } else {
      // Ad wasn't ready? Just go.
      onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isInit) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFF00FFC2))));
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller!),
          Positioned(
            top: 50, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(onTap: () => Navigator.pop(context), child: const GlassContainer(padding: EdgeInsets.all(10), borderRadius: BorderRadius.all(Radius.circular(50)), child: Icon(Icons.arrow_back, color: Colors.white))),
                GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  borderRadius: BorderRadius.circular(50),
                  child: Row(children: [const Text("BURST", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(width: 10), SizedBox(height: 20, width: 40, child: Switch(value: burstMode, activeColor: const Color(0xFF00FFC2), onChanged: (v) => setState(() => burstMode = v)))]),
                )
              ],
            ),
          ),
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _snap,
                child: Container(
                  height: 80, width: 80,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: Colors.white24),
                  child: Center(child: Container(height: 60, width: 60, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  final String path;
  const ResultPage(this.path, {super.key});
  @override Widget build(BuildContext context) => _BaseResultProcessor(task: () async => await generateRecipeWithClarifai(path), imagePath: path);
}

class ResultPageBurst extends StatelessWidget {
  final List<String> paths;
  const ResultPageBurst(this.paths, {super.key});
  @override Widget build(BuildContext context) => _BaseResultProcessor(task: () async => await generateRecipeFromPaths(paths), imagePath: paths.first);
}

// --- UPDATED PROCESSOR TO CATCH "NOT_FOOD" ERROR ---
class _BaseResultProcessor extends StatefulWidget {
  final Future<String> Function() task;
  final String imagePath;
  const _BaseResultProcessor({required this.task, required this.imagePath});
  @override State<_BaseResultProcessor> createState() => _BaseResultProcessorState();
}

class _BaseResultProcessorState extends State<_BaseResultProcessor> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _run();
  }

  Future<void> _run() async {
    try {
      final jsonText = await widget.task();
      if (!mounted) return;
      final provider = Provider.of<RecipeProvider>(context, listen: false);
      provider.setRecipe(widget.imagePath, jsonText);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RecipeRevealPage(recipe: provider.recipe!, photoPath: widget.imagePath, isHistoryView: false)));
    } catch (e) {
      if (!mounted) return;
      
      // CUSTOM ERROR HANDLING FOR NON-FOOD ITEMS
      String message = "Something went wrong.";
      String title = "Error";
      
      if (e.toString().contains("NOT_FOOD")) {
        title = "Not Edible!";
        message = "That doesn't look like food. 🛑\nTry scanning actual ingredients.";
      } else {
        message = e.toString();
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(title, style: const TextStyle(color: Colors.redAccent)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context); // Back to camera
              },
              child: const Text("Try Again", style: TextStyle(color: Color(0xFF00FFC2))),
            )
          ],
        )
      );
    }
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Image.file(File(widget.imagePath), fit: BoxFit.cover)),
          Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.black.withOpacity(0.6)))),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RotationTransition(turns: _controller, child: Container(height: 80, width: 80, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF00FFC2), width: 2), gradient: const LinearGradient(colors: [Color(0xFF00FFC2), Colors.transparent])))),
                const SizedBox(height: 30),
                Text("ALCHEMY IN PROGRESS", style: GoogleFonts.spaceMono(fontSize: 18, color: const Color(0xFF00FFC2), letterSpacing: 2)),
                const SizedBox(height: 10),
                const Text("Identifying ingredients & brewing recipe...", style: TextStyle(color: Colors.white54)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20.0, left: 20, right: 20, bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Kitchen History", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                IconButton(
                  icon: const Icon(Icons.logout, color: Color(0xFF00FFC2)),
                  tooltip: 'Sign Out',
                  onPressed: () {
                     showDialog(
                       context: context,
                       builder: (ctx) => AlertDialog(
                         backgroundColor: Colors.grey[900],
                         title: const Text("Sign Out", style: TextStyle(color: Colors.white)),
                         content: const Text("Are you sure you want to exit?", style: TextStyle(color: Colors.white70)),
                         actions: [
                           TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancel")),
                           TextButton(onPressed: (){ Navigator.pop(ctx); Provider.of<AuthProvider>(context, listen: false).signOut(); }, child: const Text("Sign Out", style: TextStyle(color: Colors.redAccent))),
                         ],
                       )
                     );
                  }
                )
              ],
            ),
          ),
          Expanded(
            child: Consumer<RecipeProvider>(
              builder: (context, provider, child) {
                if (provider.history.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Icon(Icons.history_toggle_off, size: 80, color: Colors.white.withOpacity(0.1)), const SizedBox(height: 20), const Text("No past recipes", style: TextStyle(fontSize: 18, color: Colors.white38))],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100), 
                  itemCount: provider.history.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (ctx, i) {
                    final item = provider.history[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeRevealPage(recipe: {'dish': item['dish'], 'ingredients': item['ingredients'], 'steps': item['steps']}, photoPath: item['imagePath'], isHistoryView: true))),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        height: 100,
                        child: GlassContainer(
                          padding: const EdgeInsets.all(10), opacity: 0.1,
                          child: Row(
                            children: [
                              ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(File(item['imagePath']), width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (c, o, s) => Container(color: Colors.grey[800], width: 80, height: 80, child: const Icon(Icons.broken_image)))),
                              const SizedBox(width: 15),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(item['dish'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text("Created on ${_formatDate(item['date'])}", style: const TextStyle(fontSize: 12, color: Colors.white54))])),
                              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white24)
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  String _formatDate(String? iso) { if (iso == null) return ""; final d = DateTime.parse(iso); return "${d.day}/${d.month}/${d.year}"; }
}

class RecipeRevealPage extends StatelessWidget {
  final Map<String, String> recipe;
  final String photoPath;
  final bool isHistoryView;

  const RecipeRevealPage({super.key, required this.recipe, required this.photoPath, this.isHistoryView = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Image.file(File(photoPath), fit: BoxFit.cover)),
          Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.8), Colors.black], stops: const [0.0, 0.6, 1.0])))),
          
          if(isHistoryView)
            Positioned(top: 50, left: 20, child: GestureDetector(onTap: () => Navigator.pop(context), child: const GlassContainer(padding: EdgeInsets.all(10), borderRadius: BorderRadius.all(Radius.circular(50)), child: Icon(Icons.arrow_back, color: Colors.white)))),

          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(25, 100, 25, 120),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF00FFC2), borderRadius: BorderRadius.circular(20)), child: Text(isHistoryView ? "SAVED RECIPE" : "GENERATED RECIPE", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))),
                  const SizedBox(height: 20),
                  Text(recipe['dish'] ?? 'Unknown Dish', style: GoogleFonts.playfairDisplay(fontSize: 42, fontWeight: FontWeight.bold, height: 1.1, color: Colors.white)),
                  const SizedBox(height: 30),
                  GlassContainer(color: Colors.black, opacity: 0.5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.eco_outlined, color: Color(0xFF00FFC2)), SizedBox(width: 10), Text("INGREDIENTS", style: TextStyle(color: Color(0xFF00FFC2), fontWeight: FontWeight.bold, letterSpacing: 1.2))]), const SizedBox(height: 15), Text(recipe['ingredients'] ?? '', style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70, height: 1.6))])),
                  const SizedBox(height: 20),
                  GlassContainer(color: Colors.black, opacity: 0.5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.menu_book_rounded, color: Color(0xFF00FFC2)), SizedBox(width: 10), Text("INSTRUCTIONS", style: TextStyle(color: Color(0xFF00FFC2), fontWeight: FontWeight.bold, letterSpacing: 1.2))]), const SizedBox(height: 15), Text(recipe['steps'] ?? '', style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70, height: 1.6))])),
                ],
              ),
            ),
          ),

          if (!isHistoryView)
            Positioned(
              bottom: 40, left: 20, right: 20,
              child: GestureDetector(
                onTap: () { Provider.of<RecipeProvider>(context, listen: false).saveToHistory(recipe, photoPath); Navigator.popUntil(context, (route) => route.isFirst); },
                child: Container(height: 60, decoration: BoxDecoration(color: const Color(0xFF00FFC2), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: const Color(0xFF00FFC2).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 5))]), child: const Center(child: Text("SAVE TO KITCHEN", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)))),
              ),
            ),
        ],
      ),
    );
  }
}