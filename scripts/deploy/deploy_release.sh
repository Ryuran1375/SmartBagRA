#!/bin/bash

echo "Generating release build..."
flutter build apk --release

echo "Release generated in build/app/outputs/flutter-apk/"