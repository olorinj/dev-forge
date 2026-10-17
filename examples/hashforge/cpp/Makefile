CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall
LDFLAGS ?= -lcrypto

all: hashforge-cpp

hashforge-cpp: main.cpp
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f hashforge-cpp *.o

