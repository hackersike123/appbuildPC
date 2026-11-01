// The screen-level async actions intentionally report through their active route.
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_client.dart';

part 'app/app_runtime.dart';
part 'models/product.dart';
part 'app/app_root.dart';
part 'screens/auth_screens.dart';
part 'screens/main_screen.dart';
part 'screens/home_tab.dart';
part 'screens/build_tab.dart';
part 'widgets/assembly_preview.dart';
part 'screens/market_comparison.dart';
part 'screens/product_list.dart';
part 'screens/scanner.dart';
part 'screens/compatibility.dart';
part 'screens/chat.dart';
part 'screens/saved_account.dart';
part 'screens/price_alerts.dart';
part 'widgets/shared_widgets.dart';
