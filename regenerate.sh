#!/usr/bin/env bash

flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs

echo "Code Regenerated!"
