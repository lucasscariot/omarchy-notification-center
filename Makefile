CXX ?= c++
CXXFLAGS ?= -O2 -std=c++20 -Wall -Wextra -Werror
QT_BIN ?= /usr/lib/qt6/bin
PYTHON ?= python3

.PHONY: test test-python test-qml test-gesture test-runtime helper validate

test: test-python test-qml test-touchpad test-gesture

test-python:
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=backend $(PYTHON) -m unittest discover -s tests -v

test-qml:
	QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_CONTROLS_STYLE=Basic $(QT_BIN)/qmltestrunner -import tests/imports -input tests

test-gesture: build/test_gesture
	./build/test_gesture

test-runtime:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tests/smoke_runtime.py

build:
	mkdir -p build

build/test_gesture: gestures/test_gesture.cpp gestures/gesture.hpp | build
	$(CXX) $(CXXFLAGS) $< -o $@

helper: build/edge-notifications-helper

build/edge-notifications-helper: gestures/helper.cpp gestures/gesture.hpp | build
	$(CXX) $(CXXFLAGS) $< $$(pkg-config --cflags --libs libevdev) -o $@

validate:
	omarchy plugin validate .
	@for file in *.qml; do $(QT_BIN)/qmlformat -n "$$file" >/dev/null || exit; done

.PHONY: test-touchpad
test-touchpad: build/test_touchpad_scroll
	QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software ./build/test_touchpad_scroll

build/test_touchpad_scroll: tests/touchpad_scroll.cpp | build
	$(CXX) $(CXXFLAGS) -fPIC $< $$(pkg-config --cflags --libs Qt6Quick) -o $@
