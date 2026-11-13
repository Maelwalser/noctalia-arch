# keepplace: built by hypr-plugins against the installed Hyprland headers.
CXX ?= g++
CXXFLAGS = -fPIC -g -O2 -std=c++23 -Wall -Wno-unused-parameter
# Never an executable stack: glibc 2.41+ refuses to load such a library.
LDFLAGS = -shared -Wl,-z,noexecstack
INCLUDES = $(shell pkg-config --cflags hyprland pixman-1 libdrm)
LIBS = -ldl
# Keeps two loaded copies from sharing their globals (GCC only).
ifneq ($(shell $(CXX) --version 2>/dev/null | grep -c 'Free Software Foundation'),0)
	CXXFLAGS += --no-gnu-unique
endif

BUILD ?= build
TARGET = $(BUILD)/keepplace.so

$(TARGET): main.cpp
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(LDFLAGS) -o $@ $< $(LIBS)

clean:
	rm -rf $(BUILD)

.PHONY: clean
