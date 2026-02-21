#!/bin/bash

echo "Running Flutter tests..."
flutter test

echo "Building release version..."
flutter build apk --release

echo "Tests completed successfully!"