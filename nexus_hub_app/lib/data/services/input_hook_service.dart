import 'dart:ffi';
import 'dart:io';

// FFI type definitions
typedef StartHookNative = Int32 Function();
typedef StartHookDart = int Function();

typedef StopHookNative = Int32 Function();
typedef StopHookDart = int Function();

typedef IsKeyDownNative = Int32 Function(Int32 virtualKeyCode);
typedef IsKeyDownDart = int Function(int virtualKeyCode);

typedef GetMouseXNative = Int32 Function();
typedef GetMouseXDart = int Function();

typedef GetMouseYNative = Int32 Function();
typedef GetMouseYDart = int Function();

typedef IsMouseButtonDownNative = Int32 Function(Int32 button);
typedef IsMouseButtonDownDart = int Function(int button);

typedef GetScrollDeltaNative = Int32 Function();
typedef GetScrollDeltaDart = int Function();

typedef ResetScrollDeltaNative = Void Function();
typedef ResetScrollDeltaDart = void Function();

/// Service for accessing global keyboard and mouse input state via the
/// Windows input hook DLL.
class InputHookService {
  static InputHookService? _instance;
  DynamicLibrary? _lib;
  bool _isRunning = false;

  // Native function pointers
  StartHookDart? _startHook;
  StopHookDart? _stopHook;
  IsKeyDownDart? _isKeyDown;
  GetMouseXDart? _getMouseX;
  GetMouseYDart? _getMouseY;
  IsMouseButtonDownDart? _isMouseButtonDown;
  GetScrollDeltaDart? _getScrollDelta;
  ResetScrollDeltaDart? _resetScrollDelta;

  InputHookService._();

  static InputHookService get instance {
    _instance ??= InputHookService._();
    return _instance!;
  }

  /// Initialize the DLL and start the hook. Returns true on success.
  bool initialize() {
    if (_isRunning) return true;

    try {
      // Load the DLL from the application directory
      _lib = Platform.isWindows
          ? DynamicLibrary.open('input_hook.dll')
          : DynamicLibrary.process();

      _startHook = _lib!.lookupFunction<StartHookNative, StartHookDart>(
        'StartHook',
      );
      _stopHook = _lib!.lookupFunction<StopHookNative, StopHookDart>(
        'StopHook',
      );
      _isKeyDown = _lib!.lookupFunction<IsKeyDownNative, IsKeyDownDart>(
        'IsKeyDown',
      );
      _getMouseX = _lib!.lookupFunction<GetMouseXNative, GetMouseXDart>(
        'GetMouseX',
      );
      _getMouseY = _lib!.lookupFunction<GetMouseYNative, GetMouseYDart>(
        'GetMouseY',
      );
      _isMouseButtonDown = _lib!
          .lookupFunction<IsMouseButtonDownNative, IsMouseButtonDownDart>(
            'IsMouseButtonDown',
          );
      _getScrollDelta = _lib!
          .lookupFunction<GetScrollDeltaNative, GetScrollDeltaDart>(
            'GetScrollDelta',
          );
      _resetScrollDelta = _lib!
          .lookupFunction<ResetScrollDeltaNative, ResetScrollDeltaDart>(
            'ResetScrollDelta',
          );

      final result = _startHook!();
      _isRunning = result == 0;
      return _isRunning;
    } catch (e) {
      // DLL not available or failed to load
      return false;
    }
  }

  /// Stop the hook and release resources.
  void dispose() {
    if (_isRunning && _stopHook != null) {
      _stopHook!();
      _isRunning = false;
    }
  }

  /// Check if a virtual key is currently pressed.
  bool isKeyDown(int virtualKeyCode) {
    if (!_isRunning || _isKeyDown == null) return false;
    return _isKeyDown!(virtualKeyCode) == 1;
  }

  /// Get the current mouse X coordinate.
  int get mouseX {
    if (!_isRunning || _getMouseX == null) return 0;
    return _getMouseX!();
  }

  /// Get the current mouse Y coordinate.
  int get mouseY {
    if (!_isRunning || _getMouseY == null) return 0;
    return _getMouseY!();
  }

  /// Check if a mouse button is pressed (0=left, 1=right, 2=middle).
  bool isMouseButtonDown(int button) {
    if (!_isRunning || _isMouseButtonDown == null) return false;
    return _isMouseButtonDown!(button) == 1;
  }

  /// Get the accumulated scroll delta.
  int get scrollDelta {
    if (!_isRunning || _getScrollDelta == null) return 0;
    return _getScrollDelta!();
  }

  /// Reset the accumulated scroll delta after reading.
  void resetScrollDelta() {
    if (!_isRunning || _resetScrollDelta == null) return;
    _resetScrollDelta!();
  }
}

/// Virtual key codes for Windows.
class VirtualKey {
  VirtualKey._();

  // Modifier keys (generic virtual key codes)
  static const int shift = 0x10;
  static const int control = 0x11;
  static const int menu = 0x12; // Alt
  static const int lWin = 0x5B;
  static const int rWin = 0x5C;

  // Modifier keys (left/right specific virtual key codes)
  static const int lShift = 0xA0;
  static const int rShift = 0xA1;
  static const int lControl = 0xA2;
  static const int rControl = 0xA3;
  static const int lMenu = 0xA4; // Left Alt
  static const int rMenu = 0xA5; // Right Alt

  // Modifier keys (common scan codes used by some low-level hooks)
  static const int scanLControl = 0x1D;
  static const int scanLShift = 0x2A;
  static const int scanRShift = 0x36;
  static const int scanLAlt = 0x38;
  static const int scanRAlt = 0x38E0; // extended scan code prefix
  static const int scanRControl = 0x1DE0; // extended scan code prefix

  // Standard keys
  static const int backspace = 0x08;
  static const int tab = 0x09;
  static const int enter = 0x0D;
  static const int escape = 0x1B;
  static const int space = 0x20;
  static const int pageUp = 0x21;
  static const int pageDown = 0x22;
  static const int end = 0x23;
  static const int home = 0x24;
  static const int left = 0x25;
  static const int up = 0x26;
  static const int right = 0x27;
  static const int down = 0x28;
  static const int insert = 0x2D;
  static const int delete = 0x2E;

  // Number row (0-9)
  static const int key0 = 0x30;
  static const int key1 = 0x31;
  static const int key2 = 0x32;
  static const int key3 = 0x33;
  static const int key4 = 0x34;
  static const int key5 = 0x35;
  static const int key6 = 0x36;
  static const int key7 = 0x37;
  static const int key8 = 0x38;
  static const int key9 = 0x39;

  // Letters (A-Z)
  static const int a = 0x41;
  static const int b = 0x42;
  static const int c = 0x43;
  static const int d = 0x44;
  static const int e = 0x45;
  static const int f = 0x46;
  static const int g = 0x47;
  static const int h = 0x48;
  static const int i = 0x49;
  static const int j = 0x4A;
  static const int k = 0x4B;
  static const int l = 0x4C;
  static const int m = 0x4D;
  static const int n = 0x4E;
  static const int o = 0x4F;
  static const int p = 0x50;
  static const int q = 0x51;
  static const int r = 0x52;
  static const int s = 0x53;
  static const int t = 0x54;
  static const int u = 0x55;
  static const int v = 0x56;
  static const int w = 0x57;
  static const int x = 0x58;
  static const int y = 0x59;
  static const int z = 0x5A;

  // Function keys
  static const int f1 = 0x70;
  static const int f2 = 0x71;
  static const int f3 = 0x72;
  static const int f4 = 0x73;
  static const int f5 = 0x74;
  static const int f6 = 0x75;
  static const int f7 = 0x76;
  static const int f8 = 0x77;
  static const int f9 = 0x78;
  static const int f10 = 0x79;
  static const int f11 = 0x7A;
  static const int f12 = 0x7B;

  // Numpad
  static const int numpad0 = 0x60;
  static const int numpad1 = 0x61;
  static const int numpad2 = 0x62;
  static const int numpad3 = 0x63;
  static const int numpad4 = 0x64;
  static const int numpad5 = 0x65;
  static const int numpad6 = 0x66;
  static const int numpad7 = 0x67;
  static const int numpad8 = 0x68;
  static const int numpad9 = 0x69;

  // Symbols
  static const int oemMinus = 0xBD; // -
  static const int oemPlus = 0xBB; // =
  static const int oemComma = 0xBC; // ,
  static const int oemPeriod = 0xBE; // .
  static const int oemSemicolon = 0xBA; // ;
  static const int oemTilde = 0xC0; // ~
  static const int oemOpenBrackets = 0xDB; // [
  static const int oemCloseBrackets = 0xDD; // ]
  static const int oemQuotes = 0xDE; // '
  static const int oemBackslash = 0xDC; // \
  static const int oemPipe = 0xDC; // |
  static const int oemQuestion = 0xBF; // /

  /// Returns a human-readable name for the given virtual key code.
  static String name(int code) {
    switch (code) {
      case 0x08:
        return 'Backspace';
      case 0x09:
        return 'Tab';
      case 0x0D:
        return 'Enter';
      case 0x1B:
        return 'Esc';
      case 0x20:
        return 'Space';
      case 0x21:
        return 'Page Up';
      case 0x22:
        return 'Page Down';
      case 0x23:
        return 'End';
      case 0x24:
        return 'Home';
      case 0x25:
        return 'Left';
      case 0x26:
        return 'Up';
      case 0x27:
        return 'Right';
      case 0x28:
        return 'Down';
      case 0x2D:
        return 'Insert';
      case 0x2E:
        return 'Delete';
      case 0x10:
        return 'Shift';
      case 0x11:
        return 'Ctrl';
      case 0x12:
        return 'Alt';
      case 0x5B:
        return 'Win';
      case 0x5C:
        return 'Win';
      // Left/right specific modifier virtual key codes
      case 0xA0:
        return 'Shift';
      case 0xA1:
        return 'Shift';
      case 0xA2:
        return 'Ctrl';
      case 0xA3:
        return 'Ctrl';
      case 0xA4:
        return 'Alt';
      case 0xA5:
        return 'Alt';
      // Common scan codes used by low-level hooks
      case 0x1D:
        return 'Ctrl';
      case 0x2A:
        return 'Shift';
      case 0x36:
        return 'Shift';
      case 0x38:
        return 'Alt';
      case 0x70:
        return 'F1';
      case 0x71:
        return 'F2';
      case 0x72:
        return 'F3';
      case 0x73:
        return 'F4';
      case 0x74:
        return 'F5';
      case 0x75:
        return 'F6';
      case 0x76:
        return 'F7';
      case 0x77:
        return 'F8';
      case 0x78:
        return 'F9';
      case 0x79:
        return 'F10';
      case 0x7A:
        return 'F11';
      case 0x7B:
        return 'F12';
      default:
        if (code >= 0x41 && code <= 0x5A) {
          return String.fromCharCode(code);
        }
        if (code >= 0x30 && code <= 0x39) {
          return String.fromCharCode(code);
        }
        if (code >= 0x60 && code <= 0x69) {
          return 'Numpad ${code - 0x60}';
        }
        return '0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    }
  }
}
