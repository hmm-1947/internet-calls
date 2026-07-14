import 'package:collection/collection.dart';

bool dataChanged(dynamic a, dynamic b) {
  return !const DeepCollectionEquality().equals(a, b);
}
