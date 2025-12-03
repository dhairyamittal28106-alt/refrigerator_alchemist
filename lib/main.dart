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
import 'package:image_picker/image_picker.dart';

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
  
  await Firebase.initializeApp();
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

  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    notifyListeners();
  }

  Future<void> signUpWithEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
    notifyListeners();
  }

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

// ==================== PREMIUM LOGIN UI ====================

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
          Positioned.fill(
            child: Image.network(
              "https://images.unsplash.com/photo-1550989460-0adf9ea622e2?q=80&w=1000&auto=format&fit=crop",
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(color: const Color(0xFF101010)),
            ),
          ),
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
                    const Text("Login to save your recipes.", style: TextStyle(color: Colors.white54)),
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
      case 0: return GestureDetector(onTap: _handleGoogle, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: const Center(child: Text("Continue with Google", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)))));
      case 1: return Column(children: [_inputField(_emailCtrl, "Email Address", Icons.email), const SizedBox(height: 15), _inputField(_passCtrl, "Password", Icons.lock, isPass: true), const SizedBox(height: 25), Row(children: [Expanded(child: _actionBtn("Sign Up", () => _handleEmail(false), isOutline: true)), const SizedBox(width: 10), Expanded(child: _actionBtn("Login", () => _handleEmail(true)))])]);
      default: return const SizedBox.shrink();
    }
  }

  Widget _inputField(TextEditingController ctrl, String hint, IconData icon, {bool isPass = false}) {
    return TextField(controller: ctrl, obscureText: isPass, style: const TextStyle(color: Colors.white), decoration: InputDecoration(prefixIcon: Icon(icon, color: Colors.white54), hintText: hint, hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: Colors.black26, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF00FFC2)))));
  }

  Widget _actionBtn(String text, VoidCallback onTap, {bool isOutline = false}) {
    return GestureDetector(onTap: onTap, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: isOutline ? Colors.transparent : const Color(0xFF00FFC2), border: isOutline ? Border.all(color: const Color(0xFF00FFC2)) : null, borderRadius: BorderRadius.circular(16)), child: Center(child: Text(text, style: TextStyle(color: isOutline ? const Color(0xFF00FFC2) : Colors.black, fontWeight: FontWeight.bold)))));
  }
}

// ==================== PROVIDER (WITH DELETE LOGIC) ====================

class RecipeProvider extends ChangeNotifier {
  Map<String, String>? recipe;
  String? photoPath;
  List<Map<String, dynamic>> history = [];
  int quadPoints = 0; 

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  RecipeProvider() { 
    _loadHistory();
    _loadPoints();
  }

  void setRecipe(String? path, String jsonText) {
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

  Future<void> _loadPoints() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()!.containsKey('quad_points')) {
        quadPoints = doc.data()!['quad_points'];
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> addPoints(int amount) async {
    final user = _auth.currentUser;
    if (user == null) return;
    quadPoints += amount;
    notifyListeners();
    try {
      await _db.collection('users').doc(user.uid).set({
        'quad_points': FieldValue.increment(amount)
      }, SetOptions(merge: true));
    } catch (_) {}
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

  Future<void> saveToHistory(Map<String, String> recipeData, String? tempImagePath) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      String finalPath = "";
      if (tempImagePath != null && File(tempImagePath).existsSync()) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = path_utils.basename(tempImagePath);
        final newPath = path_utils.join(directory.path, fileName);
        await File(tempImagePath).copy(newPath);
        finalPath = newPath;
      }

      final entry = {
        'dish': recipeData['dish'],
        'ingredients': recipeData['ingredients'],
        'steps': recipeData['steps'],
        'imagePath': finalPath,
        'date': DateTime.now().toIso8601String(),
        'user_email': user.email ?? user.phoneNumber ?? "Anonymous",
      };
      await _db.collection('users').doc(user.uid).collection('recipes').add(entry);
      await _loadHistory();
    } catch (e) { print("Error saving history: $e"); }
  }

  // *** NEW: DELETE FUNCTION ***
  Future<void> deleteRecipe(String docId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      // Remove from local list instantly for speed
      history.removeWhere((item) => item['id'] == docId);
      notifyListeners();
      
      // Remove from Cloud
      await _db.collection('users').doc(user.uid).collection('recipes').doc(docId).delete();
    } catch (e) {
      print("Error deleting recipe: $e");
      // Reload if error occurs
      _loadHistory();
    }
  }

  Future<void> clearHistory() async { history.clear(); notifyListeners(); }
}

// ==================== API HELPERS ====================

class ClarifaiClient {
  final String pat;
  ClarifaiClient({required this.pat});
  Future<Map<String, dynamic>> detectFoodBase64(String base64Image) async {
    final uri = Uri.parse("https://api.clarifai.com/v2/models/food-item-recognition/versions/1d5fd481e0cf4826aa72ec3ff049e044/outputs");
    final body = {"user_app_id": {"user_id": "clarifai", "app_id": "main"}, "inputs": [{"data": {"image": {"base64": base64Image}}}]};
    final res = await http.post(uri, headers: {"Authorization": "Key $pat", "Content-Type": "application/json"}, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception("Clarifai detect failed");
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

Future<Map<String, dynamic>> detectFile(String path) async {
  final pat = dotenv.env['CLARIFAI_PAT'] ?? "";
  if (pat.isEmpty) throw Exception("Missing CLARIFAI_PAT");
  final client = ClarifaiClient(pat: pat);
  final file = File(path);
  if (!await file.exists()) throw Exception("File not found");
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
    } catch (_) {}
  }
  final conceptsList = best.entries.map((e) => {"name": e.key, "value": e.value}).toList();
  return { "outputs": [ { "data": {"concepts": conceptsList} } ] };
}

List<String> _selectIngredientsFromDetectJson(Map<String, dynamic> detectJson) {
  final Map<String, double> bestScores = {};
  const double ingredientThreshold = 0.30; 
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
            if (score > highestScoreFound) highestScoreFound = score;
            if (score >= ingredientThreshold) {
              if (name.isNotEmpty && (!bestScores.containsKey(name) || bestScores[name]! < score)) {
                bestScores[name] = score;
              }
            }
          }
        }
      } catch (_) {}
    }
  } catch (_) {}

  if (bestScores.isEmpty || highestScoreFound < safetyThreshold) throw Exception("NOT_FOOD");
  return bestScores.keys.take(8).map((e) => e.replaceAll(RegExp(r'[^\w\s\-]'), '').trim()).toList();
}

Future<String> generateWithOpenRouter(String prompt) async {
  final key = dotenv.env['OPENROUTER_KEY']?.trim() ?? "";
  final base = (dotenv.env['OPENROUTER_BASE_URL'] ?? "https://openrouter.ai/api/v1").trim().replaceAll(RegExp(r'/$'), '');
  final model = dotenv.env['OPENROUTER_MODEL']?.trim() ?? "deepseek/deepseek-chat";
  if (key.isEmpty) throw Exception("Missing OPENROUTER_KEY");

  final uri = Uri.parse("$base/chat/completions");
  final body = { "model": model, "messages": [ {"role": "user", "content": prompt} ], "temperature": 0.25, "max_tokens": 450 };

  http.Response res;
  try {
    res = await http.post(uri, headers: {"Content-Type": "application/json", "Authorization": "Bearer $key"}, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
  } catch (_) {
    final uri2 = Uri.parse("$base/v1/chat/completions");
    res = await http.post(uri2, headers: {"Content-Type": "application/json", "Authorization": "Bearer $key"}, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
  }
  if (res.statusCode < 200 || res.statusCode >= 300) throw Exception("OpenRouter request failed");
  
  final dynamic jsonResp = jsonDecode(res.body);
  if (jsonResp is Map && jsonResp.containsKey('choices')) {
    final choices = jsonResp['choices'] as List;
    if (choices.isNotEmpty) {
      final msg = choices[0]['message'];
      if(msg is Map && msg['content'] != null) return msg['content'].toString().trim();
    }
  }
  return res.body; 
}

Future<String> generateRecipeFromIngredients(List<String> ingredients) async {
  final prompt = """
You are a 5-star Michelin chef. I have these ingredients: ${ingredients.join(", ")}.
Create a sophisticated yet doable recipe using them.
Return strict JSON:
{ "dish": "Dish Name", "ingredients": "• Item 1\\n• Item 2", "steps": "1. Step one...\\n2. Step two..." }
Do NOT use markdown.
""";
  final raw = await generateWithOpenRouter(prompt);
  return raw.replaceAll("```json", "").replaceAll("```", "").trim();
}

Future<String> generateRecipeFromPaths(List<String> imagePaths) async {
  if (imagePaths.isEmpty) throw Exception("No images provided");
  final List<Map<String, dynamic>> detects = [];
  for (final p in imagePaths) detects.add(await detectFile(p));
  final merged = mergeDetectJsons(detects);
  final ingredients = _selectIngredientsFromDetectJson(merged);
  return await generateRecipeFromIngredients(ingredients);
}

Future<String> generateRecipeWithClarifai(String imagePath) async => await generateRecipeFromPaths([imagePath]);

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
        child: IndexedStack(index: currentIndex, children: const [HistoryPage(), HomeCarousel()]),
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
    final isSelected = currentIndex == index && index != 2;
    return GestureDetector(
      onTap: () {
        if (index == 2) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CameraPage()));
        } else {
          setState(() => currentIndex = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFF00FFC2).withOpacity(0.2) : Colors.transparent, shape: BoxShape.circle),
        child: Icon(icon, color: (index == 2 || isSelected) ? const Color(0xFF00FFC2) : Colors.white54, size: 26),
      ),
    );
  }
}

// *** UPDATED HOME CAROUSEL WITH DOTS ***
class HomeCarousel extends StatefulWidget {
  const HomeCarousel({super.key});
  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  int _pageIndex = 0; // To track current slide for dots

  @override
  Widget build(BuildContext context) {
    final points = Provider.of<RecipeProvider>(context).quadPoints;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // LEFT: Title (No Logo)
                const Text(
                  "Fridge Alchemist", 
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2)
                ),
                // RIGHT: Points
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FFC2).withOpacity(0.2), 
                    borderRadius: BorderRadius.circular(20)
                  ),
                  child: Row(children: [
                    const Icon(Icons.bolt, color: Color(0xFF00FFC2), size: 18),
                    const SizedBox(width: 5),
                    Text(
                      "$points QP", 
                      style: const TextStyle(color: Color(0xFF00FFC2), fontWeight: FontWeight.bold)
                    ),
                  ]),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: PageController(viewportFraction: 0.85),
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) => setState(() => _pageIndex = i), // Track change
              children: const [ScanCard(), ManualInputCard()],
            ),
          ),
          
          // *** NEW: DOT INDICATORS ***
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(2, (index) => _buildDot(index)),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    bool isActive = _pageIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      height: 8,
      width: isActive ? 20 : 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF00FFC2) : Colors.white24,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class ManualInputCard extends StatelessWidget {
  const ManualInputCard({super.key});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManualEntryPage())),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: Colors.white10),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.keyboard, size: 80, color: Color(0xFF00FFC2)),
            SizedBox(height: 20),
            Text("Type Ingredients", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            Text("Don't have a photo? Type it out.", style: TextStyle(color: Colors.white54)),
          ],
        ),
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
            image: NetworkImage("https://images.unsplash.com/photo-1550989460-0adf9ea622e2?q=80&w=1000"),
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

// ==================== CAMERA PAGE WITH INTERSTITIAL ADS ====================

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? controller;
  bool isInit = false;
  bool burstMode = false;
  InterstitialAd? _interstitialAd; 

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadAd(); 
  }

  void _loadAd() {
    InterstitialAd.load(
      adUnitId: Platform.isAndroid 
        ? 'ca-app-pub-8295491395007414/9413676349' 
        : 'ca-app-pub-3940256099942544/4411468910', 
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) { ad.dispose(); _loadAd(); },
            onAdFailedToShowFullScreenContent: (ad, err) { ad.dispose(); _loadAd(); },
          );
        },
        onAdFailedToLoad: (err) { print('Ad Failed to Load: $err'); },
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

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      _showAdAndNavigate(() {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResultPage(image.path)));
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    _interstitialAd?.dispose(); 
    super.dispose();
  }

  Future<void> _snap() async {
    if (burstMode) {
      List<String> paths = [];
      for (int i = 0; i < 3; i++) {
        paths.add((await controller!.takePicture()).path);
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _showAdAndNavigate(() {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPageBurst(paths)));
      });
    } else {
      final file = await controller!.takePicture();
      _showAdAndNavigate(() {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPage(file.path)));
      });
    }
  }

  void _showAdAndNavigate(VoidCallback onDone) {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) { ad.dispose(); onDone(); _loadAd(); },
        onAdFailedToShowFullScreenContent: (ad, err) { ad.dispose(); onDone(); _loadAd(); }
      );
      _interstitialAd!.show();
      _interstitialAd = null; 
    } else {
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
            top: 50, right: 20,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              borderRadius: BorderRadius.circular(50),
              child: Row(children: [const Text("BURST", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(width: 10), SizedBox(height: 20, width: 40, child: Switch(value: burstMode, activeColor: const Color(0xFF00FFC2), onChanged: (v) => setState(() => burstMode = v)))]),
            ),
          ),
          Positioned(
            top: 50, left: 20,
            child: GestureDetector(onTap: () => Navigator.pop(context), child: const GlassContainer(padding: EdgeInsets.all(10), borderRadius: BorderRadius.all(Radius.circular(50)), child: Icon(Icons.arrow_back, color: Colors.white))),
          ),
          Positioned(
            bottom: 40, left: 30, right: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _pickFromGallery,
                  child: const CircleAvatar(radius: 25, backgroundColor: Colors.white24, child: Icon(Icons.photo_library, color: Colors.white)),
                ),
                GestureDetector(
                  onTap: _snap,
                  child: Container(height: 80, width: 80, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: Colors.white24), child: Center(child: Container(height: 60, width: 60, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)))),
                ),
                const SizedBox(width: 50),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});
  @override State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  final List<String> ingredients = [];
  final TextEditingController _controller = TextEditingController();
  bool isLoading = false;

  void _add() {
    if (_controller.text.isNotEmpty) {
      setState(() => ingredients.add(_controller.text.trim()));
      _controller.clear();
    }
  }

  Future<void> _generate() async {
    setState(() => isLoading = true);
    try {
      final jsonText = await generateRecipeFromIngredients(ingredients);
      if (!mounted) return;
      final provider = Provider.of<RecipeProvider>(context, listen: false);
      provider.setRecipe(null, jsonText);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RecipeRevealPage(recipe: provider.recipe!, photoPath: null, isHistoryView: false)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Ingredients"), backgroundColor: Colors.transparent),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "e.g. Chicken, Rice...",
                hintStyle: const TextStyle(color: Colors.white30),
                suffixIcon: IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF00FFC2)), onPressed: _add),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Wrap(
                spacing: 10,
                children: ingredients.map((e) => Chip(
                  label: Text(e),
                  backgroundColor: const Color(0xFF00FFC2),
                  onDeleted: () => setState(() => ingredients.remove(e)),
                )).toList(),
              ),
            ),
            if (isLoading) const CircularProgressIndicator(color: Color(0xFF00FFC2)),
            if (!isLoading && ingredients.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _generate,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FFC2), padding: const EdgeInsets.all(15)),
                  child: const Text("GENERATE RECIPE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              )
          ],
        ),
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
      String message = e.toString().contains("NOT_FOOD") ? "That doesn't look like food. 🛑" : "Error: $e";
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text("Oops!", style: TextStyle(color: Colors.redAccent)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [TextButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: const Text("Try Again", style: TextStyle(color: Color(0xFF00FFC2))))],
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

// ==================== HISTORY PAGE (WITH SWIPE-TO-DELETE) ====================

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  void _showProfileDialog(BuildContext context, User? user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(user?.displayName ?? "Master Chef", style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.email ?? "", style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 20),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text("Sign Out", style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                Provider.of<AuthProvider>(context, listen: false).signOut();
              },
            )
          ],
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;

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
                // *** PROFILE ICON ***
                GestureDetector(
                  onTap: () => _showProfileDialog(context, user),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                    child: user?.photoURL == null ? const Icon(Icons.person, color: Colors.white, size: 18) : null,
                  ),
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
                    
                    // *** SWIPE TO DELETE WRAPPER ***
                    return Dismissible(
                      key: Key(item['id'] ?? item.toString()),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) {
                        Provider.of<RecipeProvider>(context, listen: false).deleteRecipe(item['id']);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Recipe deleted"), backgroundColor: Colors.redAccent));
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 40),
                        color: Colors.redAccent.withOpacity(0.2),
                        child: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 32),
                      ),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeRevealPage(recipe: {'dish': item['dish'], 'ingredients': item['ingredients'], 'steps': item['steps']}, photoPath: item['imagePath'], isHistoryView: true))),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          height: 100,
                          child: GlassContainer(
                            padding: const EdgeInsets.all(10), opacity: 0.1,
                            child: Row(
                              children: [
                                ClipRRect(borderRadius: BorderRadius.circular(15), 
                                  child: (item['imagePath'] != null && item['imagePath'].isNotEmpty && File(item['imagePath']).existsSync())
                                    ? Image.file(File(item['imagePath']), width: 80, height: 80, fit: BoxFit.cover)
                                    : Container(color: Colors.grey[800], width: 80, height: 80, child: const Icon(Icons.restaurant, color: Colors.white54))
                                ),
                                const SizedBox(width: 15),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(item['dish'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text("Created on ${_formatDate(item['date'])}", style: const TextStyle(fontSize: 12, color: Colors.white54))])),
                                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white24)
                              ],
                            ),
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

class RecipeRevealPage extends StatefulWidget {
  final Map<String, String> recipe;
  final String? photoPath;
  final bool isHistoryView;

  const RecipeRevealPage({super.key, required this.recipe, required this.photoPath, this.isHistoryView = false});

  @override
  State<RecipeRevealPage> createState() => _RecipeRevealPageState();
}

class _RecipeRevealPageState extends State<RecipeRevealPage> {
  bool? isLiked; 

  void _rate(bool like) {
    if (isLiked != null) return; 
    setState(() => isLiked = like);

    if (like) {
      Provider.of<RecipeProvider>(context, listen: false).addPoints(10);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Delicious! You earned 10 Quad Points! 💎"), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Thanks for feedback! We'll improve."), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (widget.photoPath != null) 
            Positioned.fill(child: Image.file(File(widget.photoPath!), fit: BoxFit.cover))
          else
            Positioned.fill(child: Image.network("https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80", fit: BoxFit.cover)), 
            
          Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.3), Colors.black], stops: const [0.0, 0.8])))),
          
          if(widget.isHistoryView)
            Positioned(top: 50, left: 20, child: GestureDetector(onTap: () => Navigator.pop(context), child: const GlassContainer(padding: EdgeInsets.all(10), borderRadius: BorderRadius.all(Radius.circular(50)), child: Icon(Icons.arrow_back, color: Colors.white)))),

          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(25, 80, 25, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.recipe['dish'] ?? '', style: GoogleFonts.playfairDisplay(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1)),
                  const SizedBox(height: 30),
                  GlassContainer(child: Text(widget.recipe['ingredients'] ?? '', style: const TextStyle(color: Colors.white70, height: 1.5))),
                  const SizedBox(height: 20),
                  GlassContainer(child: Text(widget.recipe['steps'] ?? '', style: const TextStyle(color: Colors.white70, height: 1.5))),
                  
                  if (!widget.isHistoryView) ...[
                    const SizedBox(height: 40),
                    const Center(child: Text("Rate this Recipe", style: TextStyle(color: Colors.white54))),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: isLiked == false ? 1.2 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: IconButton(icon: Icon(Icons.thumb_down, color: isLiked == false ? Colors.redAccent : Colors.grey, size: 40), onPressed: () => _rate(false)),
                        ),
                        const SizedBox(width: 40),
                        AnimatedScale(
                          scale: isLiked == true ? 1.2 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: IconButton(icon: Icon(Icons.thumb_up, color: isLiked == true ? Colors.greenAccent : Colors.grey, size: 40), onPressed: () => _rate(true)),
                        ),
                      ],
                    ),
                  ]
                ],
              ),
            ),
          ),
          
          if (!widget.isHistoryView)
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: ElevatedButton(
                onPressed: () {
                  Provider.of<RecipeProvider>(context, listen: false).saveToHistory(widget.recipe, widget.photoPath);
                  Navigator.popUntil(context, (r) => r.isFirst);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FFC2), padding: const EdgeInsets.all(15)),
                child: const Text("SAVE & EXIT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}