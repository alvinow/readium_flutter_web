import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;

/// Configuration for Readium Navigator
class ReadiumNavigatorConfig {
  final String? stylesheetUrl;
  final Map<String, dynamic>? settings;
  final bool enableSelection;
  final bool enableTTS;

  ReadiumNavigatorConfig({
    this.stylesheetUrl,
    this.settings,
    this.enableSelection = true,
    this.enableTTS = false,
  });

  Map<String, dynamic> toJson() => {
    if (stylesheetUrl != null) 'stylesheetUrl': stylesheetUrl,
    if (settings != null) 'settings': settings,
    'enableSelection': enableSelection,
    'enableTTS': enableTTS,
  };
}

/// Location within the publication
class ReadiumLocation {
  final String href;
  final double? progression;
  final int? position;
  final Map<String, dynamic>? locator;

  ReadiumLocation({
    required this.href,
    this.progression,
    this.position,
    this.locator,
  });

  factory ReadiumLocation.fromJson(Map<String, dynamic> json) {
    return ReadiumLocation(
      href: json['href'] as String,
      progression: json['progression'] as double?,
      position: json['position'] as int?,
      locator: json['locator'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'href': href,
    if (progression != null) 'progression': progression,
    if (position != null) 'position': position,
    if (locator != null) 'locator': locator,
  };
}

/// Selection data from the reader
class ReadiumSelection {
  final String text;
  final String? locator;
  final Map<String, dynamic>? range;

  ReadiumSelection({
    required this.text,
    this.locator,
    this.range,
  });

  factory ReadiumSelection.fromJson(Map<String, dynamic> json) {
    return ReadiumSelection(
      text: json['text'] as String,
      locator: json['locator'] as String?,
      range: json['range'] as Map<String, dynamic>?,
    );
  }
}

/// Flutter wrapper for Readium HTML Navigator Injectable
class ReadiumNavigator {
  final html.IFrameElement iframe;
  final StreamController<ReadiumLocation> _locationController = StreamController<ReadiumLocation>.broadcast();
  final StreamController<ReadiumSelection> _selectionController = StreamController<ReadiumSelection>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  js.JsObject? _navigatorInstance;
  js.JsObject? _iframeWindow;
  bool _isInitialized = false;

  ReadiumNavigator(this.iframe);

  /// Stream of location changes
  Stream<ReadiumLocation> get onLocationChanged => _locationController.stream;

  /// Stream of text selections
  Stream<ReadiumSelection> get onSelection => _selectionController.stream;

  /// Stream of errors
  Stream<String> get onError => _errorController.stream;

  /// Initialize the navigator with configuration
  Future<void> initialize({
    required String navigatorScriptUrl,
    ReadiumNavigatorConfig? config,
  }) async {
    if (_isInitialized) {
      throw StateError('Navigator already initialized');
    }

    try {
      // Wait for iframe to load
      await iframe.onLoad.first;

      // Get iframe window using JS interop
      _iframeWindow = js.JsObject.fromBrowserObject(iframe)['contentWindow'] as js.JsObject;
      if (_iframeWindow == null) {
        throw Exception('Could not access iframe content window');
      }

      // Get the document from the iframe window
      final iframeDocument = _iframeWindow!['document'] as js.JsObject;

      // Create and inject the script element
      final script = iframeDocument.callMethod('createElement', ['script']) as js.JsObject;
      script['src'] = navigatorScriptUrl;
      script['type'] = 'module';

      final scriptLoaded = Completer<void>();

      // Set up onload handler
      script['onload'] = js.allowInterop((_) {
        scriptLoaded.complete();
      });

      // Set up onerror handler
      script['onerror'] = js.allowInterop((_) {
        scriptLoaded.completeError(Exception('Failed to load navigator script'));
      });

      // Append script to head
      final head = iframeDocument['head'] as js.JsObject;
      head.callMethod('appendChild', [script]);

      await scriptLoaded.future;

      // Wait a bit for the module to initialize
      await Future.delayed(const Duration(milliseconds: 100));

      // Initialize the navigator in the iframe context
      if (_iframeWindow!.hasProperty('ReadiumNavigator')) {
        final navigatorConstructor = _iframeWindow!['ReadiumNavigator'] as js.JsFunction;
        final jsConfig = js.JsObject.jsify(config?.toJson() ?? {});
        _navigatorInstance = js.JsObject(navigatorConstructor, [jsConfig]);

        // Set up event listeners
        _setupEventListeners();

        _isInitialized = true;
      } else {
        throw Exception('ReadiumNavigator not found in iframe window. Make sure the script exports it correctly.');
      }
    } catch (e) {
      _errorController.add('Initialization error: $e');
      rethrow;
    }
  }

  /// Set up event listeners for navigator events
  void _setupEventListeners() {
    if (_navigatorInstance == null) return;

    // Location changed event
    if (_navigatorInstance!.hasProperty('on')) {
      _navigatorInstance!.callMethod('on', [
        'locationChanged',
        js.allowInterop((dynamic data) {
          try {
            final jsonData = js_util.dartify(data) as Map<String, dynamic>;
            _locationController.add(ReadiumLocation.fromJson(jsonData));
          } catch (e) {
            _errorController.add('Error parsing location: $e');
          }
        }),
      ]);

      // Selection event
      _navigatorInstance!.callMethod('on', [
        'selection',
        js.allowInterop((dynamic data) {
          try {
            final jsonData = js_util.dartify(data) as Map<String, dynamic>;
            _selectionController.add(ReadiumSelection.fromJson(jsonData));
          } catch (e) {
            _errorController.add('Error parsing selection: $e');
          }
        }),
      ]);

      // Error event
      _navigatorInstance!.callMethod('on', [
        'error',
        js.allowInterop((dynamic error) {
          _errorController.add(error.toString());
        }),
      ]);
    }
  }

  /// Load a publication
  Future<void> loadPublication(String publicationUrl) async {
    _ensureInitialized();

    try {
      final result = _navigatorInstance!.callMethod('loadPublication', [publicationUrl]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
    } catch (e) {
      _errorController.add('Error loading publication: $e');
      rethrow;
    }
  }

  /// Navigate to a specific location
  Future<void> goToLocation(ReadiumLocation location) async {
    _ensureInitialized();

    try {
      final jsLocation = js.JsObject.jsify(location.toJson());
      final result = _navigatorInstance!.callMethod('goTo', [jsLocation]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
    } catch (e) {
      _errorController.add('Error navigating to location: $e');
      rethrow;
    }
  }

  /// Navigate to the next page/chapter
  Future<bool> goForward() async {
    _ensureInitialized();

    try {
      final result = _navigatorInstance!.callMethod('goForward');
      if (result != null && js_util.hasProperty(result, 'then')) {
        return await js_util.promiseToFuture<bool>(result);
      }
      return result as bool? ?? false;
    } catch (e) {
      _errorController.add('Error going forward: $e');
      return false;
    }
  }

  /// Navigate to the previous page/chapter
  Future<bool> goBackward() async {
    _ensureInitialized();

    try {
      final result = _navigatorInstance!.callMethod('goBackward');
      if (result != null && js_util.hasProperty(result, 'then')) {
        return await js_util.promiseToFuture<bool>(result);
      }
      return result as bool? ?? false;
    } catch (e) {
      _errorController.add('Error going backward: $e');
      return false;
    }
  }

  /// Get current location
  Future<ReadiumLocation?> getCurrentLocation() async {
    _ensureInitialized();

    try {
      final result = _navigatorInstance!.callMethod('getCurrentLocation');
      dynamic locationData = result;

      if (result != null && js_util.hasProperty(result, 'then')) {
        locationData = await js_util.promiseToFuture(result);
      }

      final jsonData = js_util.dartify(locationData) as Map<String, dynamic>?;
      return jsonData != null ? ReadiumLocation.fromJson(jsonData) : null;
    } catch (e) {
      _errorController.add('Error getting current location: $e');
      return null;
    }
  }

  /// Update navigator settings
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    _ensureInitialized();

    try {
      final jsSettings = js.JsObject.jsify(settings);
      final result = _navigatorInstance!.callMethod('updateSettings', [jsSettings]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
    } catch (e) {
      _errorController.add('Error updating settings: $e');
      rethrow;
    }
  }

  /// Apply a custom stylesheet
  Future<void> applyStylesheet(String stylesheetUrl) async {
    _ensureInitialized();

    try {
      final result = _navigatorInstance!.callMethod('applyStylesheet', [stylesheetUrl]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
    } catch (e) {
      _errorController.add('Error applying stylesheet: $e');
      rethrow;
    }
  }

  /// Search within the publication
  Future<List<Map<String, dynamic>>> search(String query) async {
    _ensureInitialized();

    try {
      final result = _navigatorInstance!.callMethod('search', [query]);
      dynamic searchResults = result;

      if (result != null && js_util.hasProperty(result, 'then')) {
        searchResults = await js_util.promiseToFuture(result);
      }

      final results = js_util.dartify(searchResults) as List<dynamic>;
      return results.cast<Map<String, dynamic>>();
    } catch (e) {
      _errorController.add('Error searching: $e');
      return [];
    }
  }

  /// Execute custom JavaScript in the iframe context
  dynamic executeScript(String script) {
    _ensureInitialized();

    try {
      return _iframeWindow!.callMethod('eval', [script]);
    } catch (e) {
      _errorController.add('Error executing script: $e');
      rethrow;
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized || _navigatorInstance == null) {
      throw StateError('Navigator not initialized. Call initialize() first.');
    }
  }

  /// Dispose of resources
  void dispose() {
    _locationController.close();
    _selectionController.close();
    _errorController.close();
  }
}

/// Factory for creating ReadiumNavigator instances
class ReadiumNavigatorFactory {
  /// Create a new navigator with an iframe
  static Future<ReadiumNavigator> create({
    required String containerId,
    required String navigatorScriptUrl,
    ReadiumNavigatorConfig? config,
    String? width,
    String? height,
  }) async {
    // Create iframe element
    final iframe = html.IFrameElement()
      ..id = '${containerId}_iframe'
      ..style.width = width ?? '100%'
      ..style.height = height ?? '100%'
      ..style.border = 'none';

    // Find container and append iframe
    final container = html.document.getElementById(containerId);
    if (container == null) {
      throw Exception('Container with id $containerId not found');
    }

    container.append(iframe);

    // Create and initialize navigator
    final navigator = ReadiumNavigator(iframe);
    await navigator.initialize(
      navigatorScriptUrl: navigatorScriptUrl,
      config: config,
    );

    return navigator;
  }
}