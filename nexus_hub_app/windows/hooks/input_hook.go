package main

/*
#include <windows.h>

// Forward declarations for callback trampolines
LRESULT CALLBACK KeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);
LRESULT CALLBACK MouseProc(int nCode, WPARAM wParam, LPARAM lParam);
*/
import "C"
import (
	"runtime"
	"sync"
	"unsafe"
)

// State storage
var (
	mu             sync.RWMutex
	keyStates      [256]bool
	mouseX, mouseY int32
	mouseButtons   [5]bool // 0=left, 1=right, 2=middle, 3=xbutton1, 4=xbutton2
	scrollDelta    int32
	hKeyboardHook  C.HHOOK
	hMouseHook     C.HHOOK
	running        bool
)

//export StartHook
func StartHook() int {
	// Use a channel to synchronize initialization
	resultCh := make(chan int, 1)

	go func() {
		// Lock the OS thread so that SetWindowsHookEx and the message pump
		// run on the same thread — required by WH_KEYBOARD_LL / WH_MOUSE_LL.
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		mu.Lock()

		if running {
			mu.Unlock()
			resultCh <- 1 // already running
			return
		}

		// Get the current module handle
		hMod, err := C.GetModuleHandle(nil)
		if err != nil {
			mu.Unlock()
			resultCh <- -1
			return
		}

		// Set low-level keyboard hook
		hKeyboardHook = C.SetWindowsHookEx(C.WH_KEYBOARD_LL,
			C.HOOKPROC(C.KeyboardProc),
			hMod, 0)
		if hKeyboardHook == nil {
			mu.Unlock()
			resultCh <- -2
			return
		}

		// Set low-level mouse hook
		hMouseHook = C.SetWindowsHookEx(C.WH_MOUSE_LL,
			C.HOOKPROC(C.MouseProc),
			hMod, 0)
		if hMouseHook == nil {
			C.UnhookWindowsHookEx(hKeyboardHook)
			hKeyboardHook = nil
			mu.Unlock()
			resultCh <- -3
			return
		}

		running = true
		mu.Unlock()

		resultCh <- 0

		// Run message pump on the same locked thread
		messagePump()
	}()

	return <-resultCh
}

//export StopHook
func StopHook() int {
	mu.Lock()
	defer mu.Unlock()

	if !running {
		return 0
	}

	running = false

	if hKeyboardHook != nil {
		C.UnhookWindowsHookEx(hKeyboardHook)
		hKeyboardHook = nil
	}
	if hMouseHook != nil {
		C.UnhookWindowsHookEx(hMouseHook)
		hMouseHook = nil
	}

	return 0
}

//export IsKeyDown
func IsKeyDown(virtualKeyCode int) int {
	mu.RLock()
	defer mu.RUnlock()
	if virtualKeyCode >= 0 && virtualKeyCode < 256 && keyStates[virtualKeyCode] {
		return 1
	}
	return 0
}

//export GetMouseX
func GetMouseX() int32 {
	mu.RLock()
	defer mu.RUnlock()
	return mouseX
}

//export GetMouseY
func GetMouseY() int32 {
	mu.RLock()
	defer mu.RUnlock()
	return mouseY
}

//export IsMouseButtonDown
func IsMouseButtonDown(button int) int {
	mu.RLock()
	defer mu.RUnlock()
	if button >= 0 && button < 5 && mouseButtons[button] {
		return 1
	}
	return 0
}

//export GetScrollDelta
func GetScrollDelta() int32 {
	mu.RLock()
	defer mu.RUnlock()
	return scrollDelta
}

//export ResetScrollDelta
func ResetScrollDelta() {
	mu.Lock()
	defer mu.Unlock()
	scrollDelta = 0
}

// messagePump runs a Windows message loop to process hook messages.
func messagePump() {
	var msg C.MSG
	for {
		mu.RLock()
		shouldStop := !running
		mu.RUnlock()
		if shouldStop {
			break
		}

		ret := C.GetMessage(&msg, nil, 0, 0)
		if ret == 0 {
			break
		}
		if ret == -1 {
			break
		}
		C.TranslateMessage(&msg)
		C.DispatchMessage(&msg)
	}
}

//export KeyboardProc
func KeyboardProc(nCode C.int, wParam C.WPARAM, lParam C.LPARAM) C.LRESULT {
	if nCode >= 0 {
		// Use C.KBDLLHOOKSTRUCT via direct pointer cast
		p := (*C.KBDLLHOOKSTRUCT)(unsafe.Pointer(uintptr(lParam)))
		vkCode := int(p.vkCode)

		mu.Lock()
		switch wParam {
		case C.WM_KEYDOWN, C.WM_SYSKEYDOWN:
			if vkCode >= 0 && vkCode < 256 {
				keyStates[vkCode] = true
			}
		case C.WM_KEYUP, C.WM_SYSKEYUP:
			if vkCode >= 0 && vkCode < 256 {
				keyStates[vkCode] = false
			}
		}
		mu.Unlock()
	}

	return C.CallNextHookEx(nil, nCode, wParam, lParam)
}

//export MouseProc
func MouseProc(nCode C.int, wParam C.WPARAM, lParam C.LPARAM) C.LRESULT {
	if nCode >= 0 {
		p := (*C.MSLLHOOKSTRUCT)(unsafe.Pointer(uintptr(lParam)))

		mu.Lock()
		mouseX = int32(p.pt.x)
		mouseY = int32(p.pt.y)

		switch wParam {
		case C.WM_LBUTTONDOWN:
			mouseButtons[0] = true
		case C.WM_LBUTTONUP:
			mouseButtons[0] = false
		case C.WM_RBUTTONDOWN:
			mouseButtons[1] = true
		case C.WM_RBUTTONUP:
			mouseButtons[1] = false
		case C.WM_MBUTTONDOWN:
			mouseButtons[2] = true
		case C.WM_MBUTTONUP:
			mouseButtons[2] = false
		case C.WM_XBUTTONDOWN:
			// XBUTTON1 = 0x0001, XBUTTON2 = 0x0002
			xBtn := (uintptr(p.mouseData) >> 16) & 0xFFFF
			if xBtn == 1 {
				mouseButtons[3] = true
			} else if xBtn == 2 {
				mouseButtons[4] = true
			}
		case C.WM_XBUTTONUP:
			xBtn := (uintptr(p.mouseData) >> 16) & 0xFFFF
			if xBtn == 1 {
				mouseButtons[3] = false
			} else if xBtn == 2 {
				mouseButtons[4] = false
			}
		case C.WM_MOUSEWHEEL:
			scrollDelta += int32(int16(uintptr(p.mouseData) >> 16))
		}
		mu.Unlock()
	}

	return C.CallNextHookEx(nil, nCode, wParam, lParam)
}

func main() {}
