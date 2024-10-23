#!/bin/sh

SDK_FRAMEWORK_NAME='LinkSDK'
MARKETING_VERSION="$1"
if [ -z "$SDK_FRAMEWORK_NAME" ]
  then
    echo 'Version parameter is requiredﬂ'
    exit 0
fi
CURRENT_PROJECT_VERSION=`echo ${MARKETING_VERSION%%.*}`

echo 'Building '"$SDK_FRAMEWORK_NAME"' ...'

BUILD_FOLDER='./build'
SDK_FRAMEWORK_FILENAME="$SDK_FRAMEWORK_NAME"'.xcframework'
SDK_FOLDER="$BUILD_FOLDER"'/'"$SDK_FRAMEWORK_FILENAME"
FRAMEWORK_FINAL_PATH='./'"$SDK_FRAMEWORK_FILENAME"
PLIST="$SDK_FOLDER"'/Info.plist'

rm -r $BUILD_FOLDER
rm -r $FRAMEWORK_FINAL_PATH

# build for iOS platform
xcodebuild archive \
-scheme "$SDK_FRAMEWORK_NAME" \
-configuration Release \
-destination 'generic/platform=iOS' \
-archivePath "$BUILD_FOLDER"'/'"$SDK_FRAMEWORK_NAME"'.framework-iphoneos.xcarchive' \
SKIP_INSTALL=NO \
BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
MARKETING_VERSION=$MARKETING_VERSION \
CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION

# build for iOS Simulator platform
xcodebuild archive \
-scheme "$SDK_FRAMEWORK_NAME" \
-configuration Release \
-destination 'generic/platform=iOS Simulator' \
-archivePath "$BUILD_FOLDER"'/'"$SDK_FRAMEWORK_NAME"'.framework-iphonesimulator.xcarchive' \
SKIP_INSTALL=NO \
BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
MARKETING_VERSION=$MARKETING_VERSION \
CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION

# build xcframework
xcodebuild -create-xcframework \
-framework "$BUILD_FOLDER"'/'"$SDK_FRAMEWORK_NAME"'.framework-iphonesimulator.xcarchive/Products/Library/Frameworks/'"$SDK_FRAMEWORK_NAME"'.framework' \
-framework "$BUILD_FOLDER"'/'"$SDK_FRAMEWORK_NAME"'.framework-iphoneos.xcarchive/Products/Library/Frameworks/'"$SDK_FRAMEWORK_NAME"'.framework' \
-output $SDK_FOLDER

/usr/libexec/Plistbuddy -c "Add :CFBundleVersion string $MARKETING_VERSION" "$PLIST"
/usr/libexec/Plistbuddy -c "Add :CFBundleShortVersionString string $CURRENT_PROJECT_VERSION" "$PLIST"

cp -R $SDK_FOLDER $FRAMEWORK_FINAL_PATH
rm -r $BUILD_FOLDER
