#!/bin/bash

xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar \
  -configuration Release -derivedDataPath build build \
  DEVELOPMENT_TEAM=U34SG283KY CODE_SIGN_IDENTITY="Apple Development"

open build/Build/Products/Release 
