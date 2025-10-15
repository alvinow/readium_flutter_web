import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:readium_test/readium/readium_wrapper.dart';


void main() {
  ui_web.platformViewRegistry.registerViewFactory(  // Changed this line
    'reader-container',
        (int viewId) {
      final container = html.DivElement()
        ..id = 'reader-container'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none';
      return container;
    },
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Readium Navigator Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ReadiumReaderPage(),
    );
  }
}

class ReadiumReaderPage extends StatefulWidget {
  const ReadiumReaderPage({super.key});

  @override
  State<ReadiumReaderPage> createState() => _ReadiumReaderPageState();
}

class _ReadiumReaderPageState extends State<ReadiumReaderPage> {
  ReadiumNavigator? _navigator;
  bool _isLoading = true;
  String _errorMessage = '';
  ReadiumLocation? _currentLocation;
  String _selectedText = '';
  double _progress = 0.0;

  // Configuration
  final String _navigatorScriptUrl = 'https://cdn.jsdelivr.net/npm/@readium/navigator-html-injectables/dist/index.js';
  final String _publicationUrl = 'http://localhost:15080/moby-dick.epub'; // Replace with your EPUB URL

  @override
  void initState() {
    super.initState();
    _initializeReader();
  }

  Future<void> _initializeReader() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Create the navigator
      _navigator = await ReadiumNavigatorFactory.create(
        containerId: 'reader-container',
        navigatorScriptUrl: _navigatorScriptUrl,
        config: ReadiumNavigatorConfig(
          enableSelection: true,
          enableTTS: false,
          settings: {
            'fontSize': '16px',
            'fontFamily': 'serif',
            'lineHeight': 1.5,
          },
        ),
      );

      // Set up event listeners
      _setupEventListeners();

      // Load a publication (you can replace with actual EPUB URL)
      // await _navigator!.loadPublication(_publicationUrl);

      setState(() {
        _isLoading = false;
      });

      _showSnackBar('Reader initialized successfully!');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to initialize reader: $e';
      });
      _showSnackBar('Error: $e', isError: true);
    }
  }

  void _setupEventListeners() {
    if (_navigator == null) return;

    // Listen to location changes
    _navigator!.onLocationChanged.listen((location) {
      setState(() {
        _currentLocation = location;
        _progress = location.progression ?? 0.0;
      });
      print('Location changed: ${location.href}, Progress: ${location.progression}');
    });

    // Listen to text selections
    _navigator!.onSelection.listen((selection) {
      setState(() {
        _selectedText = selection.text;
      });
      print('Text selected: ${selection.text}');
      _showSelectionDialog(selection.text);
    });

    // Listen to errors
    _navigator!.onError.listen((error) {
      print('Navigator error: $error');
      _showSnackBar('Error: $error', isError: true);
    });
  }

  Future<void> _loadPublication() async {
    if (_navigator == null) return;

    // Show dialog to input URL
    final url = await _showInputDialog(
      'Load Publication',
      'Enter EPUB URL:',
      _publicationUrl,
    );

    if (url == null || url.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _navigator!.loadPublication(url);
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Publication loaded successfully!');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to load publication: $e', isError: true);
    }
  }

  Future<void> _goForward() async {
    if (_navigator == null) return;

    final success = await _navigator!.goForward();
    if (!success) {
      _showSnackBar('Cannot go forward - end of publication');
    }
  }

  Future<void> _goBackward() async {
    if (_navigator == null) return;

    final success = await _navigator!.goBackward();
    if (!success) {
      _showSnackBar('Cannot go backward - beginning of publication');
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_navigator == null) return;

    final location = await _navigator!.getCurrentLocation();
    if (location != null) {
      _showSnackBar('Current: ${location.href} (${(location.progression ?? 0) * 100}%)');
    }
  }

  Future<void> _updateSettings() async {
    if (_navigator == null) return;

    final fontSize = await _showInputDialog(
      'Update Font Size',
      'Enter font size (e.g., 18px):',
      '16px',
    );

    if (fontSize == null || fontSize.isEmpty) return;

    try {
      await _navigator!.updateSettings({
        'fontSize': fontSize,
      });
      _showSnackBar('Settings updated!');
    } catch (e) {
      _showSnackBar('Failed to update settings: $e', isError: true);
    }
  }

  Future<void> _searchInPublication() async {
    if (_navigator == null) return;

    final query = await _showInputDialog(
      'Search',
      'Enter search term:',
      '',
    );

    if (query == null || query.isEmpty) return;

    try {
      final results = await _navigator!.search(query);
      _showSnackBar('Found ${results.length} results');
      // You can process and display results here
    } catch (e) {
      _showSnackBar('Search failed: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<String?> _showInputDialog(String title, String hint, String initial) async {
    final controller = TextEditingController(text: initial);

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSelectionDialog(String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Text Selected'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard or perform action
              Navigator.pop(context);
              _showSnackBar('Text copied!');
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _navigator?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Readium Navigator Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeReader,
            tooltip: 'Reinitialize',
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          if (_currentLocation != null)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),

          // Error message
          if (_errorMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.red[100],
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          // Reader container
          Expanded(
            child: Stack(
              children: [
                // This is where the iframe will be injected
                HtmlElementView(
                  viewType: 'reader-container',
                ),

                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.white.withOpacity(0.8),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Initializing Reader...'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Control buttons
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _loadPublication,
                  tooltip: 'Load Publication',
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBackward,
                  tooltip: 'Previous',
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _goForward,
                  tooltip: 'Next',
                ),
                IconButton(
                  icon: const Icon(Icons.location_on),
                  onPressed: _getCurrentLocation,
                  tooltip: 'Current Location',
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: _updateSettings,
                  tooltip: 'Settings',
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchInPublication,
                  tooltip: 'Search',
                ),
              ],
            ),
          ),

          // Status bar
          if (_currentLocation != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[200],
              child: Text(
                'Location: ${_currentLocation!.href} | Progress: ${(_progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

// You need to register the view factory in your web/index.html or here
// This creates the container div that will hold the iframe
void registerReaderContainer() {
  // ignore: undefined_prefixed_name
  ui_web.platformViewRegistry.registerViewFactory(
    'reader-container',
        (int viewId) {
      final container = html.DivElement()
        ..id = 'reader-container'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none';
      return container;
    },
  );
}

// Call this before runApp in main()
void setupWeb() {
  registerReaderContainer();
}

// Modified main function
void mainWithSetup() {
  setupWeb();
  runApp(const MyApp());
}