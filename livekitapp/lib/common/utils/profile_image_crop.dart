import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// Lets the user crop and zoom a picked image into a square profile photo.
///
/// Returns the cropped file, or null if the user cancelled either the
/// picker or the crop step.
Future<File?> cropProfileImage(XFile picked, {required Color brandColor}) async {
  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    compressQuality: 80,
    maxWidth: 1024,
    maxHeight: 1024,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Adjust photo',
        toolbarColor: brandColor,
        toolbarWidgetColor: Colors.white,
        backgroundColor: Colors.black,
        activeControlsWidgetColor: brandColor,
        lockAspectRatio: true,
        hideBottomControls: false,
      ),
      IOSUiSettings(
        title: 'Adjust photo',
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        rotateButtonsHidden: false,
      ),
    ],
  );
  if (cropped == null) return null;
  return File(cropped.path);
}
