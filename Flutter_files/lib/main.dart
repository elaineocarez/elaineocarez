import 'dart:async';
import 'dart:io';
import 'dart:developer' as devtools;

import 'package:flutter/material.dart';
import 'package:flutter_tflite/flutter_tflite.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    devtools.log('Firebase initialized successfully');
    devtools.log('Firebase apps count: ${Firebase.apps.length}');
  } catch (e, stackTrace) {
    devtools.log('Firebase init failed: $e', stackTrace: stackTrace);
    devtools.log('Stack trace: $stackTrace');
  }
  runApp(const ClothingIdentifierApp());
}

// ============================================================================
// APP CONFIGURATION
// ============================================================================

class ClothingIdentifierApp extends StatelessWidget {
  const ClothingIdentifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clothing Identifier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================================
// CONSTANTS & MODELS
// ============================================================================

// Helper function to clean labels by removing leading numbers
String cleanLabel(String label) {
  // Remove leading numbers and spaces (e.g., "0 Jacket" -> "Jacket")
  final regex = RegExp(r'^\d+\s*');
  return label.replaceFirst(regex, '').trim();
}

class AppConstants {
  static const String appName = 'Clothing Identifier';
  static const String appDescription = 'Identify clothing items instantly';
  
  static const List<ClothingCategory> clothingCategories = [
    ClothingCategory(id: 0, name: 'Jacket', icon: Icons.forest, color: Colors.blue),
    ClothingCategory(id: 1, name: 'Shirt', icon: Icons.checkroom, color: Colors.green),
    ClothingCategory(id: 2, name: 'Polo Shirt', icon: Icons.checkroom_outlined, color: Colors.orange),
    ClothingCategory(id: 3, name: 'Skirt', icon: Icons.woman, color: Colors.purple),
    ClothingCategory(id: 4, name: 'Shorts', icon: Icons.dry_cleaning, color: Colors.red),
    ClothingCategory(id: 5, name: 'Pants', icon: Icons.air, color: Colors.brown),
    ClothingCategory(id: 6, name: 'Socks', icon: Icons.airline_seat_legroom_reduced, color: Colors.pink),
    ClothingCategory(id: 7, name: 'Shoes', icon: Icons.airline_seat_legroom_normal, color: Colors.teal),
    ClothingCategory(id: 8, name: 'Cap', icon: Icons.face_retouching_natural, color: Colors.blueGrey),
    ClothingCategory(id: 9, name: 'Dress', icon: Icons.face_retouching_natural_outlined, color: Colors.deepPurple),
  ];
}

class ClothingCategory {
  final int id;
  final String name;
  final IconData icon;
  final Color color;

  const ClothingCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });
}

// ============================================================================
// DATABASE HELPER
// ============================================================================

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('scan_history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = path_package.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scan_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        confidence REAL NOT NULL,
        image_path TEXT NOT NULL,
        date_time TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertScan(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('scan_history', row);
  }

  Future<List<Map<String, dynamic>>> getAllScans() async {
    final db = await instance.database;
    return await db.query('scan_history', orderBy: 'id DESC');
  }

  Future<int> deleteScan(int id) async {
    final db = await instance.database;
    return await db.delete('scan_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllScans() async {
    final db = await instance.database;
    return await db.delete('scan_history');
  }

  Future<Map<String, int>> getLabelCounts() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT label, COUNT(*) as count 
      FROM scan_history 
      GROUP BY label 
      ORDER BY count DESC
    ''');
    
    final Map<String, int> labelCounts = {};
    for (var row in results) {
      labelCounts[row['label']] = row['count'] as int;
    }
    return labelCounts;
  }

  Future<Map<String, double>> getAverageConfidence() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT label, AVG(confidence) as avg_confidence 
      FROM scan_history 
      GROUP BY label 
      ORDER BY avg_confidence DESC
    ''');
    
    final Map<String, double> avgConfidence = {};
    for (var row in results) {
      avgConfidence[row['label']] = row['avg_confidence'] as double;
    }
    return avgConfidence;
  }
}

// Simple Firestore helper for sending scan logs to Firebase when available.
class FirebaseLogger {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static bool get isReady => Firebase.apps.isNotEmpty;

  static Future<bool> logScan({
    required String label,
    required double confidence,
    required String imagePath,
  }) async {
    devtools.log('=== FirebaseLogger.logScan called ===');
    devtools.log('Label: $label, Confidence: $confidence');
    devtools.log('Firebase apps count: ${Firebase.apps.length}');
    
    if (!isReady) {
      devtools.log('❌ Firebase not initialized - apps: ${Firebase.apps.length}');
      print('❌ ERROR: Firebase not initialized!');
      return false;
    }

    try {
      devtools.log('✅ Firebase is ready, attempting to save...');
      
      // Use nested collection path: Ocarez_ClothingItemClassifier/{docId}/Ocarez_ClothingItemClassifier_Logs
      const String parentCollection = 'Ocarez_ClothingItemClassifier';
      const String parentDocId = 'Ocarez_ClothingItemClassifier';
      const String logsCollection = 'Ocarez_ClothingItemClassifier_Logs';
      
      devtools.log('Collection path: $parentCollection/$parentDocId/$logsCollection');
      
      // Reference to the logs sub-collection
      final logsRef = _db
          .collection(parentCollection)
          .doc(parentDocId)
          .collection(logsCollection);
      
      final dataToSave = {
        'Accuracy_rate': confidence,
        'Class_type': label,
        'image_path': imagePath,
        'Time': FieldValue.serverTimestamp(),
      };
      
      devtools.log('Data to save: $dataToSave');
      print('🔥 Attempting to save to Firestore: $dataToSave');
      
      // Add the log document with timeout
      final docRef = await logsRef.add(dataToSave).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Firestore save operation timed out after 10 seconds');
        },
      );
      
      devtools.log('✅ Successfully saved to Firestore with ID: ${docRef.id}');
      devtools.log('Full path: $parentCollection/$parentDocId/$logsCollection/${docRef.id}');
      print('✅ SUCCESS: Saved to Firestore with ID: ${docRef.id}');
      return true;
    } on FirebaseException catch (e, stackTrace) {
      devtools.log('❌ FirebaseException: ${e.code} - ${e.message}');
      devtools.log('Stack trace: $stackTrace');
      print('❌ FIREBASE ERROR: ${e.code} - ${e.message}');
      print('❌ This might be a Firestore security rules issue!');
      return false;
    } on TimeoutException catch (e) {
      devtools.log('❌ TimeoutException: $e');
      print('❌ TIMEOUT ERROR: $e');
      return false;
    } catch (e, stackTrace) {
      devtools.log('❌ Failed to log scan to Firestore: $e');
      devtools.log('Error type: ${e.runtimeType}');
      devtools.log('Stack trace: $stackTrace');
      print('❌ UNEXPECTED ERROR: $e');
      print('❌ Error type: ${e.runtimeType}');
      return false;
    }
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

// Helper function to get current page index from route
int _getCurrentPageIndex(String? route) {
  switch (route) {
    case '/':
    case '/home':
      return 0;
    case '/categories':
      return 1;
    case '/scan':
      return 2; // Scan page still exists but not in nav bar
    case '/history':
      return 2; // History is now index 2 (was 3)
    case '/statistics':
      return 3; // Statistics is now index 3 (was 4)
    default:
      return 0;
  }
}

// Bottom Navigation Bar Widget
Widget _buildBottomNavigationBar(BuildContext context, String currentRoute) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final currentIndex = _getCurrentPageIndex(currentRoute);

  void _onItemTapped(int index) {
    final routes = [
      const HomePage(),
      const CategoriesPage(),
      const HistoryPage(),
      const StatisticsPage(),
    ];
    
    if (index != currentIndex) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => routes[index]),
      );
    }
  }

  return BottomNavigationBar(
    type: BottomNavigationBarType.fixed,
    currentIndex: currentIndex,
    onTap: _onItemTapped,
    selectedItemColor: colorScheme.primary,
    unselectedItemColor: colorScheme.onSurfaceVariant,
    backgroundColor: colorScheme.surface,
    items: const [
      BottomNavigationBarItem(
        icon: Icon(Icons.home),
        label: 'Home',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.list),
        label: 'Categories',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.history),
        label: 'History',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.bar_chart),
        label: 'Statistics',
      ),
    ],
  );
}

class AppDrawer extends StatelessWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.primary,
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: colorScheme.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.checkroom,
                    size: 60,
                    color: colorScheme.onPrimary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppConstants.appName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            _DrawerMenuItem(
              icon: Icons.camera_alt,
              title: 'Scan with Camera',
              isActive: currentRoute == '/scan',
              onTap: () {
                Navigator.pop(context);
                if (currentRoute != '/scan') {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanPage()),
                  );
                }
              },
            ),
            _DrawerMenuItem(
              icon: Icons.history,
              title: 'Scan History',
              isActive: currentRoute == '/history',
              onTap: () {
                Navigator.pop(context);
                if (currentRoute != '/history') {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryPage()),
                  );
                }
              },
            ),
            _DrawerMenuItem(
              icon: Icons.bar_chart,
              title: 'Statistics',
              isActive: currentRoute == '/statistics',
              onTap: () {
                Navigator.pop(context);
                if (currentRoute != '/statistics') {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const StatisticsPage()),
                  );
                }
              },
            ),
            const Divider(color: Colors.white30, thickness: 1, height: 30),
            _DrawerMenuItem(
              icon: Icons.list,
              title: 'Clothing Categories',
              isActive: currentRoute == '/categories',
              onTap: () {
                Navigator.pop(context);
                if (currentRoute != '/categories') {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const CategoriesPage()),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isActive;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive 
            ? colorScheme.onPrimaryContainer.withValues(alpha: 0.2) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: colorScheme.onPrimaryContainer,
          size: 28,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onPrimaryContainer,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ============================================================================
// HOME PAGE
// ============================================================================

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.primary,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // App Icon/Logo
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.checkroom,
                          size: 80,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // App Title
                      Text(
                        AppConstants.appName,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      
                      // Description
                      Text(
                        AppConstants.appDescription,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onPrimary.withValues(alpha: 0.9),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 60),
                      
                      // Get Started Button
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CategoriesPage(),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.surface,
                          foregroundColor: colorScheme.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.onPrimary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: colorScheme.onPrimary,
            size: 32,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CATEGORIES PAGE
// ============================================================================

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clothing Categories'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, '/categories'),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.primary,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Clothing Categories:',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanPage()),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.primary,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.camera_alt, size: 28),
                label: const Text(
                  'Proceed to Camera',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: AppConstants.clothingCategories.length,
                  itemBuilder: (context, index) {
                    final category = AppConstants.clothingCategories[index];
                    return _CategoryListItem(
                      category: category,
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
}

class _CategoryListItem extends StatelessWidget {
  final ClothingCategory category;

  const _CategoryListItem({required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryDetailPage(category: category),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              category.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CATEGORY DETAIL PAGE
// ============================================================================

class CategoryDetailPage extends StatelessWidget {
  final ClothingCategory category;

  const CategoryDetailPage({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        title: Text(category.name),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.primary,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tap Scan to identify this clothing item using the camera.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.surface,
                          foregroundColor: colorScheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Scan Now'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ScanPage()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCAN PAGE
// ============================================================================

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  File? _imageFile;
  String _label = "";
  double _confidence = 0.0;
  bool _isLoading = false;
  bool _isModelLoaded = false;
  String? _modelError;
  List<Map<String, dynamic>> _classConfidences = [];

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      await Tflite.loadModel(
        model: "assets/model_unquant.tflite",
        labels: "assets/labels.txt",
        numThreads: 1,
        isAsset: true,
        useGpuDelegate: false,
      );
      setState(() {
        _isModelLoaded = true;
      });
    } catch (e) {
      devtools.log("Error loading model: $e");
      if (mounted) {
        setState(() {
          _modelError = 'Failed to load AI model. Please restart the app.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error loading AI model. Please restart the app.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveToHistory() async {
    if (_imageFile != null && _label.isNotEmpty) {
      // Save to local database first
      await DatabaseHelper.instance.insertScan({
        'label': _label,
        'confidence': _confidence,
        'image_path': _imageFile!.path,
        'date_time': DateTime.now().toIso8601String(),
      });
      
      // Try to save to Firebase
      final firebaseSuccess = await FirebaseLogger.logScan(
        label: _label,
        confidence: _confidence,
        imagePath: _imageFile!.path,
      );
      
      // Show user feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              firebaseSuccess 
                ? '✓ Saved to Firestore successfully!' 
                : '⚠ Failed to save to Firestore. Check console logs for details.',
            ),
            backgroundColor: firebaseSuccess 
              ? Colors.green 
              : Colors.red,
            duration: Duration(seconds: firebaseSuccess ? 2 : 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            action: firebaseSuccess ? null : SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!_isModelLoaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text('Model is still loading. Please wait...'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image == null) return;

    setState(() {
      _isLoading = true;
      _imageFile = File(image.path);
      _label = "";
      _confidence = 0.0;
      _classConfidences = [];
    });

    try {
      final recognitions = await Tflite.runModelOnImage(
        path: image.path,
        imageMean: 0.0,
        imageStd: 255.0,
        // Ask the model for scores for all classes so the distribution list is complete
        numResults: AppConstants.clothingCategories.length,
        threshold: 0.0,
        asynch: true,
      );

      if (recognitions == null || recognitions.isEmpty) {
        devtools.log("No recognitions found");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _label = "No recognition found";
          });
        }
        return;
      }

      devtools.log(recognitions.toString());

      // Map of all known classes -> confidence (start at 0 for everyone)
      final Map<String, double> confidenceByLabel = {
        for (final cat in AppConstants.clothingCategories) cat.name: 0.0,
      };

      // Fill in confidences from model outputs
      for (var item in recognitions) {
        final label = cleanLabel(item['label'].toString());
        final rawConfidence = (item['confidence'] as num?) ?? 0;
        final confidencePercent =
            (rawConfidence * 100).toDouble().clamp(0.0, 100.0);
        if (confidenceByLabel.containsKey(label)) {
          confidenceByLabel[label] = confidencePercent;
        }
      }

      // Build list for UI (keep category order)
      final List<Map<String, dynamic>> classConfidences = [
        for (final cat in AppConstants.clothingCategories)
          {
            'label': cat.name,
            'confidence': confidenceByLabel[cat.name] ?? 0.0,
          }
      ];

      // Top class comes from highest confidence
      final topEntry = classConfidences.reduce(
        (a, b) =>
            ((a['confidence'] as double?) ?? 0.0) >= ((b['confidence'] as double?) ?? 0.0)
                ? a
                : b,
      );

      if (mounted) {
        setState(() {
          _confidence =
              (topEntry['confidence'] as double?) ?? 0.0;
          _label = (topEntry['label'] as String?) ?? '';
          _classConfidences = classConfidences;
          _isLoading = false;
        });
      }

      await _saveToHistory();
    } catch (e) {
      devtools.log("Error during recognition: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _label = "Error during recognition";
        });
      }
    }
  }

  @override
  void dispose() {
    Tflite.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Clothing Scanner"),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesPage()),
              );
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Image Display Card
              Card(
                elevation: 4,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: _imageFile == null
                      ? Container(
                          height: 300,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                size: 80,
                                color: colorScheme.onSurface,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No image selected',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                _imageFile!,
                                fit: BoxFit.contain,
                              ),
                            ),
                            if (_isLoading)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Results Card
              if (_label.isNotEmpty)
                Card(
                  color: colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          _label,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        // Top class accuracy as bar line
                         Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Accuracy",
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: (_confidence.clamp(0, 100)) / 100,
                                      minHeight: 10,
                                      backgroundColor: colorScheme.onPrimaryContainer
                                          .withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "${_confidence.toStringAsFixed(2)}%",
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              
              if (_classConfidences.isNotEmpty) ...[
                const SizedBox(height: 24),
                // Confidence Distribution List (label + % per line)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prediction distribution',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        Column(
                          children: _classConfidences.map((item) {
                            final label = (item['label'] as String?) ?? '';
                            final value =
                                (item['confidence'] as double?) ?? 0.0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: theme.textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${value.toStringAsFixed(2)}%',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // Model Loading/Error Indicator
              if (!_isModelLoaded && _modelError == null)
                Card(
                  color: colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Loading AI model...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              if (_modelError != null)
                Card(
                  color: colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _modelError!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              if ((!_isModelLoaded && _modelError == null) || _modelError != null)
                const SizedBox(height: 16),
              
              // Action Buttons
              FilledButton.icon(
                onPressed: (_isLoading || !_isModelLoaded)
                    ? null
                    : () => _pickImage(ImageSource.camera),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.camera_alt),
                label: const Text(
                  "Take a Photo",
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: (_isLoading || !_isModelLoaded)
                    ? null
                    : () => _pickImage(ImageSource.gallery),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.photo_library),
                label: const Text(
                  "Pick From Gallery",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HISTORY PAGE
// ============================================================================

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getAllScans();
    setState(() {
      _history = data;
      _isLoading = false;
    });
  }

  Future<void> _deleteItem(int id) async {
    await DatabaseHelper.instance.deleteScan(id);
    _loadHistory();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All History'),
        content: const Text('Are you sure you want to delete all scan history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteAllScans();
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAll,
              tooltip: 'Clear All',
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, '/history'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 80,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No scan history yet',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      final dateTime = DateTime.parse(item['date_time']);
                      final formattedDate = DateFormat('MMM dd, yyyy hh:mm a').format(dateTime);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: item['image_path'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(item['image_path']),
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 60,
                                        height: 60,
                                        color: colorScheme.surfaceContainerHighest,
                                        child: Icon(
                                          Icons.broken_image,
                                          color: colorScheme.onSurface,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : null,
                          title: Text(
                            cleanLabel(item['label']),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Accuracy: ${item['confidence'].toStringAsFixed(0)}%',
                              ),
                              Text(
                                formattedDate,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteItem(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================================
// STATISTICS PAGE
// ============================================================================

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  Map<String, int> _labelCounts = {};
  Map<String, double> _avgConfidence = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    final counts = await DatabaseHelper.instance.getLabelCounts();
    final avgConf = await DatabaseHelper.instance.getAverageConfidence();
    
    setState(() {
      _labelCounts = counts;
      _avgConfidence = avgConf;
      _isLoading = false;
    });
  }

  List<Color> _generateColors(int count) {
    return List.generate(count, (index) {
      final hue = (index * 360 / count) % 360;
      return HSVColor.fromAHSV(1.0, hue, 0.7, 0.9).toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context, '/statistics'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _labelCounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bar_chart,
                        size: 80,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No data available yet.\nStart scanning clothing!',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStatistics,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Total Scans Card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatCard(
                                  icon: Icons.qr_code_scanner,
                                  value: '${_labelCounts.values.reduce((a, b) => a + b)}',
                                  label: 'Total Scans',
                                ),
                                _buildStatCard(
                                  icon: Icons.category,
                                  value: '${_labelCounts.length}',
                                  label: 'Clothing Types',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Scan Frequency Card (line graph + list)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scan Frequency',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 220,
                                  child: LineChart(
                                    LineChartData(
                                      minY: 0,
                                      maxY: _getMaxFrequencyY().toDouble(),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: _buildFrequencySpots(),
                                          isCurved: true,
                                          color: colorScheme.primary,
                                          barWidth: 3,
                                          dotData: FlDotData(show: true),
                                          belowBarData: BarAreaData(show: false),
                                        ),
                                      ],
                                      titlesData: FlTitlesData(
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 32,
                                            getTitlesWidget: (value, meta) {
                                              return Text(
                                                value.toInt().toString(),
                                                style: theme.textTheme.bodySmall,
                                              );
                                            },
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 40,
                                            getTitlesWidget: (value, meta) {
                                              final index = value.toInt();
                                              final labels = _getFrequencyLabels();
                                              if (index < 0 || index >= labels.length) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 8),
                                                child: Text(
                                                  labels[index],
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    fontSize: 8,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                      ),
                                      borderData: FlBorderData(
                                        show: true,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: colorScheme.outlineVariant,
                                            width: 1,
                                          ),
                                          left: BorderSide(
                                            color: colorScheme.outlineVariant,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Scans by Category',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Column(
                                  children: _getFrequencyEntries().map((entry) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              cleanLabel(entry.key),
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                                            child: Text(
                                              entry.value.toString(),
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Pie Chart
                        Text(
                          'Scan Distribution',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                              height: 300,
                              child: PieChart(
                                PieChartData(
                                  sections: _buildPieSections(),
                                  centerSpaceRadius: 50,
                                  sectionsSpace: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildLegend(),
                        
                        const SizedBox(height: 32),
                        
                        // Line Chart
                        Text(
                          'Average Accuracy',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                              height: 300,
                              child: Stack(
                                children: [
                                  LineChart(
                                    LineChartData(
                                      maxY: 100,
                                      minY: 0,
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: _buildLineSpots(),
                                          isCurved: true,
                                          color: colorScheme.primary,
                                          barWidth: 3,
                                          dotData: FlDotData(
                                            show: true,
                                            getDotPainter: (spot, percent, barData, index) {
                                              return FlDotCirclePainter(
                                                radius: 5,
                                                color: colorScheme.primary,
                                                strokeWidth: 2,
                                                strokeColor: colorScheme.surface,
                                              );
                                            },
                                          ),
                                          belowBarData: BarAreaData(show: false),
                                        ),
                                      ],
                                      titlesData: FlTitlesData(
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 40,
                                            getTitlesWidget: (value, meta) {
                                              return Text('${value.toInt()}%');
                                            },
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (value, meta) {
                                              if (value.toInt() < _avgConfidence.length) {
                                                final label = cleanLabel(_avgConfidence.keys.toList()[value.toInt()]);
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 8),
                                                  child: Text(
                                                    label.length > 10 
                                                        ? '${label.substring(0, 10)}...' 
                                                        : label,
                                                    style: const TextStyle(fontSize: 10),
                                                  ),
                                                );
                                              }
                                              return const Text('');
                                            },
                                          ),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        getDrawingHorizontalLine: (value) {
                                          return FlLine(
                                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                                            strokeWidth: 1,
                                          );
                                        },
                                      ),
                                      borderData: FlBorderData(
                                        show: true,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: colorScheme.onSurfaceVariant,
                                            width: 1,
                                          ),
                                          left: BorderSide(
                                            color: colorScheme.onSurfaceVariant,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      lineTouchData: LineTouchData(
                                        touchTooltipData: LineTouchTooltipData(
                                          getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                            return touchedSpots.map((LineBarSpot touchedSpot) {
                                              return LineTooltipItem(
                                                '${touchedSpot.y.toInt()}%',
                                                TextStyle(
                                                  color: colorScheme.onPrimary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              );
                                            }).toList();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Percentage labels above points
                                  ..._buildPercentageLabels(theme.textTheme, colorScheme),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Icon(icon, size: 40),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label),
      ],
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    final colors = _generateColors(_labelCounts.length);
    final total = _labelCounts.values.reduce((a, b) => a + b);
    
    return _labelCounts.entries.map((entry) {
      final index = _labelCounts.keys.toList().indexOf(entry.key);
      final percentage = (entry.value / total * 100);
      
      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        color: colors[index],
        radius: 100,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildLegend() {
    final colors = _generateColors(_labelCounts.length);
    
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: _labelCounts.entries.map((entry) {
        final index = _labelCounts.keys.toList().indexOf(entry.key);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colors[index],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text('${cleanLabel(entry.key)} (${entry.value})'),
          ],
        );
      }).toList(),
    );
  }

  // Helpers for scan frequency chart
  List<MapEntry<String, int>> _getFrequencyEntries() {
    // Ensure all known categories are present, in a consistent order
    final List<MapEntry<String, int>> entries = [];
    for (final cat in AppConstants.clothingCategories) {
      entries.add(MapEntry(cat.name, _labelCounts[cat.name] ?? 0));
    }
    return entries;
  }

  List<FlSpot> _buildFrequencySpots() {
    final entries = _getFrequencyEntries();
    return entries
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value.toDouble()))
        .toList();
  }

  int _getMaxFrequencyY() {
    if (_labelCounts.isEmpty) return 1;
    final maxVal = _labelCounts.values.reduce((a, b) => a > b ? a : b);
    return maxVal == 0 ? 1 : maxVal + 1;
  }

  List<String> _getFrequencyLabels() {
    return _getFrequencyEntries().map((e) => cleanLabel(e.key)).toList();
  }

  List<FlSpot> _buildLineSpots() {
    return _avgConfidence.entries.toList().asMap().entries.map((entry) {
      final index = entry.key;
      final value = entry.value.value;
      return FlSpot(index.toDouble(), value);
    }).toList();
  }

  List<Widget> _buildPercentageLabels(TextTheme textTheme, ColorScheme colorScheme) {
    if (_avgConfidence.isEmpty) return [];
    
    // Chart dimensions accounting for padding and axis labels
    final chartWidth = 268.0; // 300 - 16*2 (padding)
    final chartHeight = 268.0; // 300 - 16*2 (padding)
    final leftPadding = 50.0; // Space for left axis labels
    final bottomPadding = 50.0; // Space for bottom axis labels
    final topPadding = 20.0; // Space for top labels
    final maxY = 100.0;
    final minY = 0.0;
    final spots = _buildLineSpots();
    
    if (spots.isEmpty) return [];
    
    return spots.asMap().entries.map((entry) {
      final index = entry.key;
      final spot = entry.value;
      
      // Calculate X position (distribute evenly across chart width)
      final xPercent = spots.length > 1 ? index / (spots.length - 1) : 0.5;
      final x = leftPadding + (xPercent * (chartWidth - leftPadding));
      
      // Calculate Y position (invert because Y=0 is at top in Flutter)
      final yPercent = 1.0 - ((spot.y - minY) / (maxY - minY));
      final availableHeight = chartHeight - bottomPadding - topPadding;
      final y = topPadding + (yPercent * availableHeight) - 20.0; // Position above point
      
      return Positioned(
        left: x - 20,
        top: y.clamp(0, chartHeight - 25),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            '${spot.y.toInt()}%',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
      );
    }).toList();
  }
}
