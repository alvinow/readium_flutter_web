import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPUB Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EpubReaderPage(),
    );
  }
}

class EpubReaderPage extends StatefulWidget {
  const EpubReaderPage({super.key});

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  bool _isLoading = true;
  bool _isReaderReady = false;
  String _errorMessage = '';
  List<String> _debugLogs = [];
  String _currentChapter = '';
  double _progress = 0.0;
  String _viewType = '';
  html.IFrameElement? _iframe;
  bool _isIframeReady = false;

  @override
  void initState() {
    super.initState();
    _initializeReader();
  }

  void _addDebugLog(String message) {
    print('DEBUG: $message');
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _debugLogs.add('${DateTime.now().toString().substring(11, 19)}: $message');
            if (_debugLogs.length > 20) {
              _debugLogs.removeAt(0);
            }
          });
        }
      });
    }
  }

  Future<void> _initializeReader() async {
    setState(() {
      _isLoading = true;
      _isReaderReady = false;
      _errorMessage = '';
      _debugLogs.clear();
      _isIframeReady = false;
    });

    _addDebugLog('Starting initialization...');

    try {
      _viewType = 'epub-reader-view-${DateTime.now().millisecondsSinceEpoch}';
      _addDebugLog('View type: $_viewType');

      _iframe = html.IFrameElement()
        ..id = _viewType
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none';

      // FIXED: Simplified HTML with direct JSZip and EPUB.js from CDN
      _iframe!.srcdoc = '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { 
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              background: #f5f5f5;
              overflow: hidden;
            }
            #viewer { 
              width: 100%; 
              height: 100vh; 
              background: white;
              position: relative;
              z-index: 1;
            }
            #controls {
              position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
              background: rgba(0,0,0,0.85); padding: 12px 24px; border-radius: 12px;
              display: none; gap: 12px; z-index: 1000; box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            }
            button {
              background: #2196f3; color: white; border: none; padding: 10px 20px;
              border-radius: 6px; cursor: pointer; font-size: 14px; font-weight: 500;
            }
            button:hover { background: #1976d2; }
            #status {
              position: fixed; top: 20px; right: 20px;
              background: rgba(33, 150, 243, 0.95); color: white;
              padding: 12px 20px; border-radius: 8px; font-size: 13px;
              max-width: 350px; z-index: 1001; box-shadow: 0 2px 8px rgba(0,0,0,0.2);
            }
            .loading {
              display: flex; flex-direction: column; align-items: center;
              justify-content: center; height: 100vh; gap: 20px;
            }
            .spinner {
              border: 4px solid #f3f3f3; border-top: 4px solid #2196f3;
              border-radius: 50%; width: 50px; height: 50px;
              animation: spin 1s linear infinite;
            }
            @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
            .welcome {
              display: flex; flex-direction: column; align-items: center;
              justify-content: center; height: 100vh; gap: 16px; color: #666;
            }
            .welcome-icon { font-size: 80px; }
          </style>
        </head>
        <body>
          <div id="status">Initializing...</div>
          <div id="viewer">
            <div class="welcome">
              <div class="welcome-icon">📚</div>
              <h2>EPUB Reader Ready</h2>
              <p>Load an EPUB to begin</p>
            </div>
          </div>
          <div id="controls">
            <button onclick="prevPage()">◄ Prev</button>
            <button onclick="nextPage()">Next ►</button>
          </div>
          
          <!-- Load JSZip first, then EPUB.js -->
          <script src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/epubjs/dist/epub.min.js"></script>
          
          <script>
            let book = null;
            let rendition = null;
            
            function log(msg) {
              console.log('[EPUB]', msg);
            }
            
            function updateStatus(msg) {
              document.getElementById('status').textContent = msg;
              log('Status: ' + msg);
              sendToParent({ type: 'status', message: msg });
            }
            
            function sendToParent(data) {
              try {
                if (window.parent) window.parent.postMessage(data, '*');
              } catch (e) { console.error('Send error:', e); }
            }
            
            function showControls(show) {
              document.getElementById('controls').style.display = show ? 'flex' : 'none';
            }
            
            async function loadEpub(url) {
              log('Loading: ' + url);
              updateStatus('Loading EPUB...');
              
              try {
                if (rendition) {
                  try { rendition.destroy(); } catch (e) {}
                }
                
                const viewer = document.getElementById('viewer');
                viewer.innerHTML = '<div class="loading"><div class="spinner"></div><p>Loading EPUB...</p></div>';
                
                log('Creating book...');
                book = ePub(url);
                
                log('Waiting for ready...');
                await book.ready;
                log('Book ready!');
                
                const metadata = await book.loaded.metadata;
                log('Metadata: ' + metadata.title);
                updateStatus('Rendering...');
                
                log('Creating rendition...');
                rendition = book.renderTo("viewer", {
                  width: "100%",
                  height: "100%",
                  spread: "none"
                });
                
                log('Displaying...');
                await rendition.display();
                
                // Force viewer to show content and remove loading
                const viewerEl = document.getElementById('viewer');
                if (viewerEl) {
                  viewerEl.style.opacity = '1';
                  viewerEl.style.visibility = 'visible';
                  // Remove any loading overlays
                  const loadingDivs = viewerEl.querySelectorAll('.loading');
                  loadingDivs.forEach(div => div.remove());
                }
                
                log('SUCCESS! Book displayed!');
                
                // Debug: Check what's in the viewer
                setTimeout(() => {
                  const iframes = document.querySelectorAll('iframe');
                  log('Found ' + iframes.length + ' iframes in viewer');
                  if (iframes.length > 0) {
                    log('Iframe dimensions: ' + iframes[0].offsetWidth + 'x' + iframes[0].offsetHeight);
                  }
                }, 500);
                
                updateStatus('📖 ' + (metadata.title || 'Ready'));
                showControls(true);
                sendToParent({ type: 'ready' });
                
                // Events
                rendition.on('relocated', (loc) => {
                  if (book.locations && book.locations.total > 0) {
                    const pct = book.locations.percentageFromCfi(loc.start.cfi);
                    sendToParent({
                      type: 'locationChanged',
                      location: { href: loc.start.href, progression: pct }
                    });
                  }
                });
                
                // Background location generation
                book.locations.generate(1024).then(() => {
                  log('Locations generated');
                }).catch(e => log('Location gen failed: ' + e));
                
              } catch (e) {
                log('ERROR: ' + e.message);
                updateStatus('Error: ' + e.message);
                viewer.innerHTML = '<div class="welcome"><div style="font-size: 60px;">⚠️</div><h2>Error</h2><p>' + e.message + '</p></div>';
                sendToParent({ type: 'error', message: e.message });
              }
            }
            
            function prevPage() { if (rendition) rendition.prev(); }
            function nextPage() { if (rendition) rendition.next(); }
            
            function changeFontSize(size) {
              if (rendition) {
                rendition.themes.fontSize(size + 'px');
                updateStatus('Font: ' + size + 'px');
              }
            }
            
            function changeTheme(theme) {
              if (rendition) {
                if (theme === 'dark') {
                  rendition.themes.override('color', '#e0e0e0');
                  rendition.themes.override('background', '#1a1a1a');
                } else if (theme === 'sepia') {
                  rendition.themes.override('color', '#5b4636');
                  rendition.themes.override('background', '#f4ecd8');
                } else {
                  rendition.themes.override('color', '#000');
                  rendition.themes.override('background', '#fff');
                }
                updateStatus('Theme: ' + theme);
              }
            }
            
            window.addEventListener('message', (e) => {
              const d = e.data;
              if (d.action === 'loadEpub') loadEpub(d.url);
              else if (d.action === 'next') nextPage();
              else if (d.action === 'prev') prevPage();
              else if (d.action === 'fontSize') changeFontSize(d.size);
              else if (d.action === 'theme') changeTheme(d.theme);
              else if (d.action === 'ping') sendToParent({ type: 'pong' });
            });
            
            document.addEventListener('keydown', (e) => {
              if (e.key === 'ArrowLeft') prevPage();
              if (e.key === 'ArrowRight') nextPage();
            });
            
            setTimeout(() => {
              updateStatus('✓ Ready');
              sendToParent({ type: 'initialized' });
            }, 300);
          </script>
        </body>
        </html>
      ''';

      _addDebugLog('Created iframe with EPUB.js');

      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
            (int viewId) {
          _addDebugLog('Platform view factory called with viewId: $viewId');
          return _iframe!;
        },
      );

      _addDebugLog('Registered platform view: $_viewType');

      html.window.onMessage.listen((event) {
        final data = event.data;
        if (data is Map) {
          _handleIframeMessage(data);
        }
      });

      await Future.delayed(const Duration(milliseconds: 1500));

      setState(() {
        _isLoading = false;
        _isReaderReady = true;
      });

      _showSnackBar('✓ Reader initialized!');
      _addDebugLog('✓ Initialization complete');

      await Future.delayed(const Duration(milliseconds: 500));
      _testIframeCommunication();

    } catch (e, stackTrace) {
      _addDebugLog('❌ ERROR: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to initialize: $e';
      });
      _showSnackBar('Error: $e', isError: true);
    }
  }

  void _testIframeCommunication() {
    _addDebugLog('Testing iframe communication...');
    Future.delayed(const Duration(milliseconds: 100), () {
      _sendMessageToIframe({'action': 'ping'});
    });
  }

  void _handleIframeMessage(Map data) {
    if (!mounted) return; // Add safety check

    final type = data['type'];
    _addDebugLog('◀ Received: $type');

    if (type == 'status') {
      _addDebugLog('Status: ${data['message']}');
    } else if (type == 'initialized') {
      if (mounted) setState(() => _isIframeReady = true);
      _addDebugLog('✓ Iframe ready');
    } else if (type == 'pong') {
      if (mounted) setState(() => _isIframeReady = true);
      _addDebugLog('✓ Communication OK');
    } else if (type == 'ready') {
      _addDebugLog('✓ EPUB loaded!');
      if (mounted) _showSnackBar('✓ EPUB loaded!');
    } else if (type == 'error') {
      _addDebugLog('❌ Error: ${data['message']}');
      if (mounted) _showSnackBar('Error: ${data['message']}', isError: true);
    } else if (type == 'locationChanged') {
      final location = data['location'];
      if (mounted) {
        setState(() {
          _currentChapter = location['href'] ?? '';
          _progress = (location['progression'] ?? 0.0).toDouble();
        });
      }
    }
  }

  void _sendMessageToIframe(Map<String, dynamic> message) {
    try {
      if (_iframe?.contentWindow != null) {
        _iframe!.contentWindow!.postMessage(message, '*');
        _addDebugLog('▶ Sent: ${message['action']}');
      }
    } catch (e) {
      _addDebugLog('⚠️ Send failed: $e');
    }
  }

  Future<void> _loadEpub() async {
    _addDebugLog('📖 _loadEpub() called');

    if (!_isIframeReady) {
      _showSnackBar('Iframe not ready yet', isError: true);
      return;
    }

    final url = await _showInputDialog(
      'Load EPUB',
      'Enter EPUB URL:',
      'https://s3.amazonaws.com/moby-dick/moby-dick.epub',
    );

    if (url == null || url.isEmpty) return;

    _addDebugLog('📖 Loading: $url');
    _sendMessageToIframe({
      'action': 'loadEpub',
      'url': url,
    });
  }

  void _nextPage() {
    if (!_isIframeReady) return;
    _sendMessageToIframe({'action': 'next'});
  }

  void _prevPage() {
    if (!_isIframeReady) return;
    _sendMessageToIframe({'action': 'prev'});
  }

  Future<void> _changeFontSize() async {
    final size = await _showInputDialog('Font Size', 'Enter size (12-32):', '18');
    if (size == null || size.isEmpty) return;

    final fontSize = int.tryParse(size) ?? 18;
    _sendMessageToIframe({'action': 'fontSize', 'size': fontSize});
  }

  Future<void> _changeTheme() async {
    final theme = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Theme'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'light'),
            child: const Text('☀️ Light'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'dark'),
            child: const Text('🌙 Dark'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'sepia'),
            child: const Text('📖 Sepia'),
          ),
        ],
      ),
    );

    if (theme != null) {
      _sendMessageToIframe({'action': 'theme', 'theme': theme});
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  Future<String?> _showInputDialog(String title, String hint, String initial) async {
    final controller = TextEditingController(text: initial);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(null),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
                autofocus: true,
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                    child: const Text('Load'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    controller.dispose();
    return result;
  }

  void _showDebugLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Logs'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _debugLogs.isEmpty
              ? const Center(child: Text('No logs'))
              : ListView.builder(
            itemCount: _debugLogs.length,
            itemBuilder: (context, i) => Text(_debugLogs[i], style: const TextStyle(fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EPUB Reader'),
        actions: [
          IconButton(icon: const Icon(Icons.bug_report), onPressed: _showDebugLogs),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _initializeReader),
        ],
      ),
      body: Column(
        children: [
          if (_progress > 0)
            LinearProgressIndicator(value: _progress, minHeight: 3),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isReaderReady
                ? HtmlElementView(viewType: _viewType)
                : const Center(child: Text('Not initialized')),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(icon: const Icon(Icons.folder_open), onPressed: _loadEpub),
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: _prevPage),
                IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _nextPage),
                IconButton(icon: const Icon(Icons.text_fields), onPressed: _changeFontSize),
                IconButton(icon: const Icon(Icons.palette), onPressed: _changeTheme),
              ],
            ),
          ),
        ],
      ),
    );
  }
}