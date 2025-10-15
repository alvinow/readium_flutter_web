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
      progression: (json['progression'] as num?)?.toDouble(),
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
  final StreamController<ReadiumLocation> _locationController =
  StreamController<ReadiumLocation>.broadcast();
  final StreamController<ReadiumSelection> _selectionController =
  StreamController<ReadiumSelection>.broadcast();
  final StreamController<String> _errorController =
  StreamController<String>.broadcast();

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

  /// Check if navigator is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the navigator with configuration
  Future<void> initialize({
    required String navigatorScriptUrl,
    ReadiumNavigatorConfig? config,
  }) async {
    if (_isInitialized) {
      throw StateError('Navigator already initialized');
    }

    try {
      print('ReadiumNavigator: Waiting for iframe to load...');

      // Wait for iframe to load
      await iframe.onLoad.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Iframe load timeout after 10 seconds');
        },
      );

      print('ReadiumNavigator: Iframe loaded, accessing window...');

      // Get iframe window using JS interop
      _iframeWindow = js.JsObject.fromBrowserObject(iframe)['contentWindow'] as js.JsObject;
      if (_iframeWindow == null) {
        throw Exception('Could not access iframe content window');
      }

      print('ReadiumNavigator: Got iframe window, accessing document...');

      // Get the document from the iframe window
      final iframeDocument = _iframeWindow!['document'] as js.JsObject;

      print('ReadiumNavigator: Creating script element...');

      // Create and inject the script element
      final script = iframeDocument.callMethod('createElement', ['script']) as js.JsObject;
      script['src'] = navigatorScriptUrl;
      script['type'] = 'module';

      final scriptLoaded = Completer<void>();

      // Set up onload handler
      script['onload'] = js.allowInterop((_) {
        print('ReadiumNavigator: Script loaded successfully from $navigatorScriptUrl');
        scriptLoaded.complete();
      });

      // Set up onerror handler
      script['onerror'] = js.allowInterop((error) {
        print('ReadiumNavigator: Script load error - $error');
        scriptLoaded.completeError(
            Exception('Failed to load navigator script from $navigatorScriptUrl')
        );
      });

      print('ReadiumNavigator: Appending script to document head...');

      // Append script to head
      final head = iframeDocument['head'] as js.JsObject;
      head.callMethod('appendChild', [script]);

      // Wait for script to load
      await scriptLoaded.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Script load timeout after 10 seconds');
        },
      );

      print('ReadiumNavigator: Script loaded, waiting for module initialization...');

      // Wait a bit for the module to initialize
      await Future.delayed(const Duration(milliseconds: 200));

      print('ReadiumNavigator: Checking for ReadiumNavigator in iframe window...');

      // Initialize the navigator in the iframe context
      if (_iframeWindow!.hasProperty('ReadiumNavigator')) {
        print('ReadiumNavigator: Found ReadiumNavigator class, creating instance...');

        final navigatorConstructor = _iframeWindow!['ReadiumNavigator'] as js.JsFunction;
        final jsConfig = js.JsObject.jsify(config?.toJson() ?? {});
        _navigatorInstance = js.JsObject(navigatorConstructor, [jsConfig]);

        print('ReadiumNavigator: Instance created, setting up event listeners...');

        // Set up event listeners
        _setupEventListeners();

        _isInitialized = true;
        print('ReadiumNavigator: Initialization complete!');
      } else {
        print('ReadiumNavigator: ReadiumNavigator class not found in iframe window');
        print('Available properties: ${_iframeWindow!.toString()}');
        throw Exception(
            'ReadiumNavigator not found in iframe window. '
                'The script may not export it globally, or it may use a different export name.'
        );
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Initialization error: $e';
      print('ReadiumNavigator ERROR: $errorMsg');
      print('Stack trace: $stackTrace');
      _errorController.add(errorMsg);
      rethrow;
    }
  }

  /// Set up event listeners for navigator events
  void _setupEventListeners() {
    if (_navigatorInstance == null) return;

    print('ReadiumNavigator: Setting up event listeners...');

    // Check if the instance has an 'on' method for event listening
    if (!_navigatorInstance!.hasProperty('on')) {
      print('ReadiumNavigator: Warning - instance does not have "on" method for events');
      return;
    }

    try {
      // Location changed event
      _navigatorInstance!.callMethod('on', [
        'locationChanged',
        js.allowInterop((dynamic data) {
          try {
            print('ReadiumNavigator: Location changed event received');
            final jsonData = js_util.dartify(data) as Map<String, dynamic>;
            _locationController.add(ReadiumLocation.fromJson(jsonData));
          } catch (e) {
            final errorMsg = 'Error parsing location: $e';
            print('ReadiumNavigator: $errorMsg');
            _errorController.add(errorMsg);
          }
        }),
      ]);

      // Selection event
      _navigatorInstance!.callMethod('on', [
        'selection',
        js.allowInterop((dynamic data) {
          try {
            print('ReadiumNavigator: Selection event received');
            final jsonData = js_util.dartify(data) as Map<String, dynamic>;
            _selectionController.add(ReadiumSelection.fromJson(jsonData));
          } catch (e) {
            final errorMsg = 'Error parsing selection: $e';
            print('ReadiumNavigator: $errorMsg');
            _errorController.add(errorMsg);
          }
        }),
      ]);

      // Error event
      _navigatorInstance!.callMethod('on', [
        'error',
        js.allowInterop((dynamic error) {
          final errorMsg = error.toString();
          print('ReadiumNavigator: Error event - $errorMsg');
          _errorController.add(errorMsg);
        }),
      ]);

      print('ReadiumNavigator: Event listeners configured');
    } catch (e) {
      print('ReadiumNavigator: Error setting up event listeners - $e');
    }
  }

  /// Load a publication
  Future<void> loadPublication(String publicationUrl) async {
    _ensureInitialized();

    print('ReadiumNavigator: Loading publication from $publicationUrl');

    try {
      final result = _navigatorInstance!.callMethod('loadPublication', [publicationUrl]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
      print('ReadiumNavigator: Publication loaded successfully');
    } catch (e) {
      final errorMsg = 'Error loading publication: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      rethrow;
    }
  }

  /// Navigate to a specific location
  Future<void> goToLocation(ReadiumLocation location) async {
    _ensureInitialized();

    print('ReadiumNavigator: Going to location ${location.href}');

    try {
      final jsLocation = js.JsObject.jsify(location.toJson());
      final result = _navigatorInstance!.callMethod('goTo', [jsLocation]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
      print('ReadiumNavigator: Navigation complete');
    } catch (e) {
      final errorMsg = 'Error navigating to location: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      rethrow;
    }
  }

  /// Navigate to the next page/chapter
  Future<bool> goForward() async {
    _ensureInitialized();

    print('ReadiumNavigator: Going forward');

    try {
      final result = _navigatorInstance!.callMethod('goForward');
      if (result != null && js_util.hasProperty(result, 'then')) {
        final success = await js_util.promiseToFuture<bool>(result);
        print('ReadiumNavigator: Go forward ${success ? "successful" : "failed"}');
        return success;
      }
      return result as bool? ?? false;
    } catch (e) {
      final errorMsg = 'Error going forward: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      return false;
    }
  }

  /// Navigate to the previous page/chapter
  Future<bool> goBackward() async {
    _ensureInitialized();

    print('ReadiumNavigator: Going backward');

    try {
      final result = _navigatorInstance!.callMethod('goBackward');
      if (result != null && js_util.hasProperty(result, 'then')) {
        final success = await js_util.promiseToFuture<bool>(result);
        print('ReadiumNavigator: Go backward ${success ? "successful" : "failed"}');
        return success;
      }
      return result as bool? ?? false;
    } catch (e) {
      final errorMsg = 'Error going backward: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      return false;
    }
  }

  /// Get current location
  Future<ReadiumLocation?> getCurrentLocation() async {
    _ensureInitialized();

    print('ReadiumNavigator: Getting current location');

    try {
      final result = _navigatorInstance!.callMethod('getCurrentLocation');
      dynamic locationData = result;

      if (result != null && js_util.hasProperty(result, 'then')) {
        locationData = await js_util.promiseToFuture(result);
      }

      final jsonData = js_util.dartify(locationData) as Map<String, dynamic>?;
      if (jsonData != null) {
        final location = ReadiumLocation.fromJson(jsonData);
        print('ReadiumNavigator: Current location - ${location.href}');
        return location;
      }
      return null;
    } catch (e) {
      final errorMsg = 'Error getting current location: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      return null;
    }
  }

  /// Update navigator settings
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    _ensureInitialized();

    print('ReadiumNavigator: Updating settings - $settings');

    try {
      final jsSettings = js.JsObject.jsify(settings);
      final result = _navigatorInstance!.callMethod('updateSettings', [jsSettings]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
      print('ReadiumNavigator: Settings updated successfully');
    } catch (e) {
      final errorMsg = 'Error updating settings: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      rethrow;
    }
  }

  /// Apply a custom stylesheet
  Future<void> applyStylesheet(String stylesheetUrl) async {
    _ensureInitialized();

    print('ReadiumNavigator: Applying stylesheet from $stylesheetUrl');

    try {
      final result = _navigatorInstance!.callMethod('applyStylesheet', [stylesheetUrl]);
      if (result != null && js_util.hasProperty(result, 'then')) {
        await js_util.promiseToFuture(result);
      }
      print('ReadiumNavigator: Stylesheet applied successfully');
    } catch (e) {
      final errorMsg = 'Error applying stylesheet: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      rethrow;
    }
  }

  /// Search within the publication
  Future<List<Map<String, dynamic>>> search(String query) async {
    _ensureInitialized();

    print('ReadiumNavigator: Searching for "$query"');

    try {
      final result = _navigatorInstance!.callMethod('search', [query]);
      dynamic searchResults = result;

      if (result != null && js_util.hasProperty(result, 'then')) {
        searchResults = await js_util.promiseToFuture(result);
      }

      final results = js_util.dartify(searchResults) as List<dynamic>;
      print('ReadiumNavigator: Search found ${results.length} results');
      return results.cast<Map<String, dynamic>>();
    } catch (e) {
      final errorMsg = 'Error searching: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      return [];
    }
  }

  /// Execute custom JavaScript in the iframe context
  dynamic executeScript(String script) {
    _ensureInitialized();

    print('ReadiumNavigator: Executing custom script');

    try {
      return _iframeWindow!.callMethod('eval', [script]);
    } catch (e) {
      final errorMsg = 'Error executing script: $e';
      print('ReadiumNavigator: $errorMsg');
      _errorController.add(errorMsg);
      rethrow;
    }
  }

  /// Get the iframe window object for advanced operations
  js.JsObject? get iframeWindow => _iframeWindow;

  /// Get the navigator instance for advanced operations
  js.JsObject? get navigatorInstance => _navigatorInstance;

  void _ensureInitialized() {
    if (!_isInitialized || _navigatorInstance == null) {
      throw StateError('Navigator not initialized. Call initialize() first.');
    }
  }

  /// Dispose of resources
  void dispose() {
    print('ReadiumNavigator: Disposing resources');
    _locationController.close();
    _selectionController.close();
    _errorController.close();
    _isInitialized = false;
    _navigatorInstance = null;
    _iframeWindow = null;
  }
}