#!/bin/bash
set -e

# Set up Java
export JAVA_HOME=$(ls -d $HOME/java/jdk-21*/Contents/Home)
export ANDROID_HOME=$HOME/android-sdk

# Generate Gradle wrapper if needed
if [ ! -f gradle/wrapper/gradle-wrapper.jar ]; then
    echo "Generating Gradle wrapper..."
    /tmp/gradle-8.5/bin/gradle wrapper
fi

# Build APK
echo "Building APK..."
/tmp/gradle-8.5/bin/gradle assembleDebug --no-daemon

# Copy to desktop
APK=$(find app/build/outputs -name "*.apk" | head -1)
if [ -n "$APK" ]; then
    cp "$APK" ~/Desktop/NetDiagnose.apk
    SIZE=$(ls -lh "$APK" | awk '{print $5}')
    echo "✅ APK saved to ~/Desktop/NetDiagnose.apk ($SIZE)"
else
    echo "❌ Build failed"
    exit 1
fi
