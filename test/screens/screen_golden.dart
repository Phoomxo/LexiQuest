import 'dart:io';

// Linux and Windows rasterize the same bundled Thai font differently.
String screenGolden(String filename) =>
    Platform.isLinux ? 'goldens/linux/$filename' : 'goldens/$filename';
