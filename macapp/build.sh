#!/bin/bash

xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar \
  -configuration Release -derivedDataPath build build

open build/Build/Products/Release 
